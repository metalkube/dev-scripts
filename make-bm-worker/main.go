package main

import (
	"encoding/base64"
	"flag"
	"fmt"
	"os"
	"strings"
	"text/template"
)

const (
	instanceImageSource      = "http://172.22.0.1/images/redhat-coreos-maipo-latest.qcow2"
	instanceImageChecksumURL = instanceImageSource + ".md5sum"
)

var templateBody = `---
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Name }}-bmc-secret
type: Opaque
data:
  username: {{ .EncodedUsername }}
  password: {{ .EncodedPassword }}

---
apiVersion: metalkube.org/v1alpha1
kind: BareMetalHost
metadata:
  name: {{ .Name }}
spec:
  online: true
  bmc:
    address: {{ .BMCAddress }}
    credentialsName: {{ .Name }}-bmc-secret
{{- if .WithImage }}
  userData:
    namespace: openshift-machine-api
    name: worker-user-data
  image:
    url: "{{ .ImageSourceURL }}"
    checksum: "{{ .Checksum }}"
{{ end -}}
`

// TemplateArgs holds the arguments to pass to the template.
type TemplateArgs struct {
	Name            string
	BMCAddress      string
	EncodedUsername string
	EncodedPassword string
	WithImage       bool
	Checksum        string
	ImageSourceURL  string
}

func encodeToSecret(input string) string {
	return base64.StdEncoding.EncodeToString([]byte(input))
}

func main() {
	var username = flag.String("user", "", "username for BMC")
	var password = flag.String("password", "", "password for BMC")
	var bmcAddress = flag.String("address", "", "address URL for BMC")
	var verbose = flag.Bool("v", false, "turn on verbose output")
	var withImage = flag.Bool("image", false, "include the image settings to trigger deployment")

	flag.Parse()

	hostName := flag.Arg(0)
	if hostName == "" {
		fmt.Fprintf(os.Stderr, "Missing name argument\n")
		os.Exit(1)
	}
	if *username == "" {
		fmt.Fprintf(os.Stderr, "Missing -user argument\n")
		os.Exit(1)
	}
	if *password == "" {
		fmt.Fprintf(os.Stderr, "Missing -password argument\n")
		os.Exit(1)
	}
	if *bmcAddress == "" {
		fmt.Fprintf(os.Stderr, "Missing -address argument\n")
		os.Exit(1)
	}

	args := TemplateArgs{
		Name:            strings.Replace(hostName, "_", "-", -1),
		BMCAddress:      *bmcAddress,
		EncodedUsername: encodeToSecret(*username),
		EncodedPassword: encodeToSecret(*password),
		WithImage:       *withImage,
		Checksum:        instanceImageChecksumURL,
		ImageSourceURL:  instanceImageSource,
	}
	if *verbose {
		fmt.Fprintf(os.Stderr, "%v", args)
	}

	t := template.Must(template.New("yaml_out").Parse(templateBody))
	err := t.Execute(os.Stdout, args)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: %s\n", err)
	}
}
