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

// literal resolves only syntax-local strings, never identifiers or runtime values.
func literal(expr ast.Expr) (string, bool) {
	switch value := expr.(type) {
	case *ast.BasicLit:
		if value.Kind == token.STRING {
			text, err := strconv.Unquote(value.Value)
			return text, err == nil
		}
	case *ast.ParenExpr:
		return literal(value.X)
	case *ast.BinaryExpr:
		if value.Op == token.ADD {
			left, leftOK := literal(value.X)
			right, rightOK := literal(value.Y)
			return left + right, leftOK && rightOK
		}
	}
	return "", false
}

// guidance retains separate text boundaries and joins literal argument lists only.
func guidance(source []byte) ([]string, error) {
	file, err := parser.ParseFile(token.NewFileSet(), "surface.go", source, parser.ParseComments|parser.AllErrors)
	if err != nil {
		return nil, err
	}
	var parts []string
	for _, group := range file.Comments {
		for _, comment := range group.List {
			parts = append(parts, comment.Text)
		}
	}
	joinArgs := func(expressions []ast.Expr) {
		var args []string
		complete, hasJSON := true, false
		for _, expression := range expressions {
			text, ok := literal(expression)
			complete = complete && ok
			hasJSON = hasJSON || text == "--json" || strings.HasPrefix(text, "--json=")
			// Keyed/dynamic expressions cannot hide a known JSON flag inside the list.
			ast.Inspect(expression, func(node ast.Node) bool {
				if expr, ok := node.(ast.Expr); ok {
					value, known := literal(expr)
					hasJSON = hasJSON || known && (value == "--json" || strings.HasPrefix(value, "--json="))
				}
				return true
			})
			args = append(args, text)
		}
		if !complete && hasJSON {
			err = fmt.Errorf("Go JSON argument list contains unresolved values")
		}
		if complete && hasJSON {
			parts = append(parts, strings.Join(args, " "))
		}
	}
	ast.Inspect(file, func(node ast.Node) bool {
		switch value := node.(type) {
		case *ast.BasicLit:
			if value.Kind == token.STRING {
				text, ok := literal(value)
				if !ok {
					err = fmt.Errorf("Go string could not be decoded")
				} else {
					parts = append(parts, text)
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
			if name != "" {
				switch name {
				case "Command":
					joinArgs(value.Args)
				case "CommandContext":
					if len(value.Args) > 0 {
						joinArgs(value.Args[1:])
					}
				}
			}
		case *ast.CompositeLit:
			if array, ok := value.Type.(*ast.ArrayType); ok {
				if element, ok := array.Elt.(*ast.Ident); ok && element.Name == "string" {
					joinArgs(value.Elts)
				}
			}
		case *ast.BinaryExpr:
			if text, ok := literal(value); ok {
				parts = append(parts, text)
			}
		}
		return true
	})
	if err != nil {
		return nil, err
	}
	return parts, nil
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
