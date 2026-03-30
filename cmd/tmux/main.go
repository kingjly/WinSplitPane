package main

import (
	"os"

	"winsplitpane/internal/app"
)

func main() {
	application, err := app.New(os.Stdout, os.Stderr)
	if err != nil {
		_, _ = os.Stderr.WriteString(err.Error() + "\n")
		os.Exit(1)
	}

	os.Exit(application.Run(os.Args[1:]))
}
