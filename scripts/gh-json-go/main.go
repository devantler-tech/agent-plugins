// Decode Go guidance without executing or compiling the inspected source.
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"io"
	"os"
	"strconv"
	"strings"
)

type decoder struct {
	steps, bytes int
	parts        []string
	err          error
}

func (d *decoder) step() bool {
	if d.err != nil {
		return false
	}
	d.steps++
	if d.steps > 262144 {
		d.err = fmt.Errorf("Go syntax work exceeds the observation budget")
	}
	return d.err == nil
}

// Reserve before creating concatenations, so a small source cannot expand without bound.
func (d *decoder) reserve(size int) bool {
	if d.err != nil {
		return false
	}
	if size > (4<<20)-d.bytes {
		d.err = fmt.Errorf("Go decoded text exceeds the observation budget")
		return false
	}
	d.bytes += size
	return true
}

// literal resolves only syntax-local strings, never identifiers or runtime values.
func (d *decoder) literal(expr ast.Expr) (string, bool) {
	if !d.step() {
		return "", false
	}
	switch value := expr.(type) {
	case *ast.BasicLit:
		if value.Kind == token.STRING {
			text, err := strconv.Unquote(value.Value)
			if err != nil {
				d.err = err
				return "", false
			}
			return text, d.reserve(len(text))
		}
	case *ast.ParenExpr:
		return d.literal(value.X)
	case *ast.BinaryExpr:
		if value.Op == token.ADD {
			left, leftOK := d.literal(value.X)
			right, rightOK := d.literal(value.Y)
			if leftOK && rightOK && d.reserve(len(left)+len(right)) {
				return left + right, true
			}
		}
	}
	return "", false
}

func (d *decoder) emit(text string) {
	if d.step() && d.reserve(len(text)) {
		d.parts = append(d.parts, text)
	}
}

func (d *decoder) hasFlag(expression ast.Expr) bool {
	flag := false
	ast.Inspect(expression, func(node ast.Node) bool {
		if node == nil || !d.step() {
			return false
		}
		if value, ok := node.(ast.Expr); ok {
			text, known := d.literal(value)
			if known {
				flag = flag || text == "--json" || strings.HasPrefix(text, "--json=")
				return false
			}
		}
		return true
	})
	return flag
}

func (d *decoder) joinArgs(expressions []ast.Expr) {
	var args []string
	complete, hasJSON := true, false
	for _, expression := range expressions {
		text, ok := d.literal(expression)
		complete = complete && ok
		hasJSON = d.hasFlag(expression) || hasJSON
		args = append(args, text)
	}
	if !complete && hasJSON && d.err == nil {
		d.err = fmt.Errorf("Go JSON argument grouping contains unresolved values")
	}
	if complete && hasJSON {
		size := len(args) - 1
		for _, arg := range args {
			size += len(arg)
		}
		if d.reserve(size) {
			d.emit(strings.Join(args, " "))
		}
	}
}

// guidance retains separate text boundaries and joins literal argument blocks only.
func guidance(source []byte) ([]string, error) {
	file, err := parser.ParseFile(token.NewFileSet(), "surface.go", source, parser.ParseComments|parser.AllErrors)
	if err != nil {
		return nil, err
	}
	d := &decoder{}
	for _, group := range file.Comments {
		for _, comment := range group.List {
			d.emit(comment.Text)
		}
	}
	ast.Inspect(file, func(node ast.Node) bool {
		if node == nil || !d.step() {
			return false
		}
		switch value := node.(type) {
		case *ast.BasicLit, *ast.BinaryExpr, *ast.ParenExpr:
			if expression, ok := node.(ast.Expr); ok {
				if text, known := d.literal(expression); known {
					d.emit(text)
					return false // Retain only the maximal literal, never all its prefixes.
				}
			}
		case *ast.CallExpr:
			name := ""
			switch function := value.Fun.(type) {
			case *ast.SelectorExpr:
				name = function.Sel.Name
			case *ast.Ident:
				name = function.Name
			}
			switch name {
			case "Command":
				d.joinArgs(value.Args)
			case "CommandContext":
				if len(value.Args) > 0 {
					d.joinArgs(value.Args[1:])
				}
			}
		case *ast.CompositeLit:
			// Named/inferred types cannot silently split a known flag from its fields.
			// Nested/keyed/dynamic groupings are UNKNOWN when literal argv is unresolved.
			d.joinArgs(value.Elts)
		}
		return d.err == nil
	})
	if d.err != nil {
		return nil, d.err
	}
	return d.parts, nil
}

func run() error {
	if len(os.Args) != 2 {
		return fmt.Errorf("one retained source path is required")
	}
	input, err := os.Open(os.Args[1])
	if err != nil {
		return err
	}
	defer input.Close()
	const maximum = 8 << 20
	source, err := io.ReadAll(io.LimitReader(input, maximum+1))
	if err != nil || len(source) > maximum {
		return fmt.Errorf("Go source could not be completely read within 8 MiB")
	}
	parts, err := guidance(source)
	if err != nil {
		return err
	}
	_, err = io.WriteString(os.Stdout, strings.Join(parts, "\n%\n")+"\n%\n")
	return err
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
}
