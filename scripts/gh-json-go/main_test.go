package main

import (
	"go/ast"
	"go/token"
	"strconv"
	"strings"
	"testing"
)

func TestGuidance(t *testing.T) {
	tests := []struct {
		name, source, want string
		unknown            bool
	}{
		{"comment", "package p\n// gh pr view --json merged\n", "--json merged", false},
		{"escaped", `package p; const x = "--json mer\u0067ed"`, "--json merged", false},
		{"raw", "package p; const x = `--json merged`", "--json merged", false},
		{"concatenated", `package p; const x = "--json mer" + "ged"`, "--json merged", false},
		{"command", `package p; var x = exec.Command("gh", "pr", "view", "--json", "merged")`, "--json merged", false},
		{"context", `package p; var x = exec.CommandContext(ctx, "gh", "pr", "view", "--json", "merged")`, "--json merged", false},
		{"dot import", `package p; var x = Command("gh", "pr", "view", "--json", "merged")`, "--json merged", false},
		{"argv", `package p; var x = []string{"--json", "merged"}`, "--json merged", false},
		{"named argv", `package p; type argv []string; var x = argv{"--json", "merged"}`, "--json merged", false},
		{"inferred nested argv", `package p; var x = [][]string{{"--json", "merged"}}`, "", true},
		{"dynamic", `package p; var x = []string{"--json", fields}`, "", true},
		{"dynamic command", `package p; var x = exec.Command("gh", "--json", fields)`, "", true},
		{"keyed argv", `package p; var x = []string{0:"--json", 1:"merged"}`, "", true},
		{"malformed", `package p; func broken(`, "", true},
		{"no execution", `package p; func init(){ panic("never execute") }`, "never execute", false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			parts, err := guidance([]byte(test.source))
			if (err != nil) != test.unknown {
				t.Fatalf("unknown=%v, error=%v", test.unknown, err)
			}
			if !test.unknown && !strings.Contains(strings.Join(parts, "\n%\n"), test.want) {
				t.Fatalf("missing observed text %q in %q", test.want, parts)
			}
			if test.unknown && parts != nil {
				t.Fatal("incomplete parsing returned partial success")
			}
		})
	}
}

func TestMaximalConcatenation(t *testing.T) {
	parts, err := guidance([]byte("package p; const x = " + strings.Repeat(`"a"+`, 127) + `"a"`))
	if err != nil {
		t.Fatal(err)
	}
	if len(parts) != 1 || parts[0] != strings.Repeat("a", 128) {
		t.Fatal("concatenation prefixes were repeatedly retained")
	}
}

func TestDecodedBudget(t *testing.T) {
	parts, err := guidance([]byte("package p; const x = " + strconv.Quote(strings.Repeat("x", (4<<20)+1))))
	if err == nil || parts != nil {
		t.Fatal("oversized decoded output did not return UNKNOWN")
	}
}

func TestSeparateStrings(t *testing.T) {
	parts, err := guidance([]byte(`package p; var notes = []string{"The CLI option --json", "merged is invalid"}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, part := range parts {
		if strings.Contains(part, "--json merged") {
			t.Fatalf("unrelated notes were joined: %q", part)
		}
	}
}

func TestKnownArgumentsAreDecodedOnce(t *testing.T) {
	value := strings.Repeat("x", 1200000)
	d := &decoder{}
	d.joinArgs([]ast.Expr{
		&ast.BasicLit{Kind: token.STRING, Value: `"--json"`},
		&ast.BasicLit{Kind: token.STRING, Value: strconv.Quote(value)},
	})
	if d.err != nil || len(d.parts) != 1 || d.parts[0] != "--json "+value {
		t.Fatalf("known argv was redundantly decoded: %v", d.err)
	}
}

// TestManyMarkdownSpans preserves literal guidance across many successive code spans.
func TestManyMarkdownSpans(t *testing.T) {
	source := strings.Repeat("Use ``gh pr view --json state,mergedAt``. ", 10000)
	text, err := normalizeShellFields(source)
	if err != nil || text != source {
		t.Fatalf("repeated literal guidance changed: %v", err)
	}
}

// TestDecodedGuidanceBoundary prevents one retained value from supplying another's opener.
func TestDecodedGuidanceBoundary(t *testing.T) {
	_, err := normalizeShellFields("An unmatched ` belongs to another decoded value.\n%\ngh pr view --json state,mer`printf ged`\n%\n")
	if err == nil {
		t.Fatal("a separate decoded value supplied a misleading Markdown opener")
	}
}

// TestHeadingGuidanceBoundaries refuses delimiter inheritance across separate Markdown blocks.
func TestHeadingGuidanceBoundaries(t *testing.T) {
	for _, source := range []string{
		"# Heading with a literal `\ngh pr view --json state,mer`printf ged`",
		"Prior paragraph with a literal `\n# gh pr view --json state,mer`printf ged`",
		"Heading with a literal `\n=======================\ngh pr view --json state,mer`printf ged`",
		"Paragraph with a literal `\n---\ngh pr view --json state,mer`printf ged`",
		"Paragraph with a literal `\n***\ngh pr view --json state,mer`printf ged`",
		">     echo `literal\n> gh pr view --json state,mer`printf ged`",
		"<!-- Literal ` marker -->\ngh pr view --json state,mer`printf ged`",
	} {
		if _, err := normalizeShellFields(source); err == nil {
			t.Errorf("a separate Markdown block supplied a misleading opener: %q", source)
		}
	}
}

// BenchmarkMarkdownSpans measures normalization at two input sizes while preserving all text.
func BenchmarkMarkdownSpans(b *testing.B) {
	for _, count := range []int{1000, 10000} {
		// Each size checks the full normalized output during every timed iteration.
		b.Run(strconv.Itoa(count), func(b *testing.B) {
			source := strings.Repeat("Use ``gh pr view --json state,mergedAt``. ", count)
			b.SetBytes(int64(len(source)))
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				text, err := normalizeShellFields(source)
				if err != nil || text != source {
					b.Fatalf("literal guidance changed: %v", err)
				}
			}
		})
	}
}
