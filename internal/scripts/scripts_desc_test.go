package scripts

import "testing"

func TestExtractScriptDescriptionOSHeaders(t *testing.T) {
	cases := []struct {
		name string
		body string
		want string
	}{
		{
			name: "shell hash purpose",
			body: "#!/bin/bash\n# Purpose: Wrapper to run iostat extended stats\n",
			want: "Wrapper to run iostat extended stats",
		},
		{
			name: "python hash purpose",
			body: "#!/usr/bin/env python\n# Purpose: Process and thread CPU memory IO stats via /proc\n",
			want: "Process and thread CPU memory IO stats via /proc",
		},
		{
			name: "c slash purpose",
			body: "// Purpose: Linux memory alloc free read write stress tool\n",
			want: "Linux memory alloc free read write stress tool",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := extractScriptDescription([]byte(tc.body)); got != tc.want {
				t.Fatalf("extractScriptDescription() = %q, want %q", got, tc.want)
			}
		})
	}
}
