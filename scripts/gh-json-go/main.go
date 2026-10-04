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

// step bounds all syntax visits and stops work after the first observation failure.
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

// emit charges retained output to the same sticky observation budget.
func (d *decoder) emit(text string) {
	if d.step() && d.reserve(len(text)) {
		d.parts = append(d.parts, text)
	}
}

// hasFlag searches unresolved groups for a syntax-local JSON flag.
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

// joinArgs joins complete literal argv and refuses incomplete groups beside a known flag.
func (d *decoder) joinArgs(expressions []ast.Expr) {
	var args []string
	complete, hasJSON := true, false
	for _, expression := range expressions {
		text, ok := d.literal(expression)
		complete = complete && ok
		if ok {
			hasJSON = hasJSON || text == "--json" || strings.HasPrefix(text, "--json=")
		} else {
			hasJSON = d.hasFlag(expression) || hasJSON
		}
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

type markdownObserver struct {
	position, delimiter, fenceLength, blockEnd int
	fence                                      byte
}

// markdownContentStart skips quote/list markers only when their container syntax is complete.
func markdownContentStart(source string, start, end int) (int, bool) {
	for start < end {
		markerEnd := start
		switch source[start] {
		case '>':
			markerEnd++
		case '-', '+', '*':
			markerEnd++
			if markerEnd == end || !strings.ContainsRune(" \t", rune(source[markerEnd])) {
				return start, false
			}
		default:
			for markerEnd < end && markerEnd-start < 9 && source[markerEnd] >= '0' && source[markerEnd] <= '9' {
				markerEnd++
			}
			if markerEnd == start || markerEnd+1 >= end ||
				(source[markerEnd] != '.' && source[markerEnd] != ')') ||
				!strings.ContainsRune(" \t", rune(source[markerEnd+1])) {
				return start, false
			}
			markerEnd++
		}
		start = markerEnd
		if start < end && source[start] == ' ' {
			start++ // Consume the container's optional/required separator only.
		}
		indent := start
		for start < end && start-indent < 4 && source[start] == ' ' {
			start++
		}
		if start-indent == 4 || start < end && source[start] == '\t' {
			return start, true
		}
	}
	return start, false
}

// delimiterAt advances once through source and observes the inline span before a field flag.
// Matching runs close spans; escaped prose and fenced/indented blocks cannot open them.
func (m *markdownObserver) delimiterAt(source string, stop int) int {
	delimiter, fence, fenceLength := m.delimiter, m.fence, m.fenceLength
	i := m.position
	for i < stop {
		if m.blockEnd > 0 && i >= m.blockEnd {
			delimiter, m.blockEnd = 0, 0
		}
		if i == 0 || source[i-1] == '\n' {
			lineEnd := strings.IndexByte(source[i:], '\n')
			if lineEnd < 0 {
				lineEnd = len(source)
			} else {
				lineEnd += i
			}
			start := i
			for start < lineEnd && start-i < 4 && source[start] == ' ' {
				start++
			}
			indented := start-i == 4 || start < lineEnd && source[start] == '\t'
			if !indented {
				var containerIndented bool
				start, containerIndented = markdownContentStart(source, start, lineEnd)
				if containerIndented {
					indented, delimiter = true, 0
				}
			}
			content := strings.Trim(source[start:lineEnd], " \t\r")
			if content == "" || strings.Trim(source[i:lineEnd], " \t\r") == "%" {
				delimiter = 0 // Paragraph and retained-value boundaries cannot supply an opener.
			}
			if fence == 0 && !indented && content != "" {
				if strings.HasPrefix(source[start:], "<!--") {
					delimiter = 0 // Raw HTML comments cannot open Markdown code spans.
					closing := strings.Index(source[start+4:], "-->")
					if closing < 0 {
						i = len(source)
					} else {
						i = start + 4 + closing + 3
					}
					continue
				}
				heading := 0
				for heading < len(content) && content[heading] == '#' {
					heading++
				}
				if heading > 0 && heading <= 6 && (heading == len(content) || strings.ContainsRune(" \t", rune(content[heading]))) {
					delimiter = 0
					m.blockEnd = lineEnd + 1 // A heading's inline content ends on this line.
				}
				if strings.Trim(content, "=") == "" || strings.Trim(content, "- \t") == "" ||
					strings.Trim(content, "* \t") == "" && strings.Count(content, "*") >= 3 ||
					strings.Trim(content, "_ \t") == "" && strings.Count(content, "_") >= 3 {
					delimiter = 0 // Setext headings and thematic breaks end the prior paragraph.
					i = lineEnd + 1
					continue
				}
			}
			if !indented && start < lineEnd && (source[start] == '`' || source[start] == '~') {
				end := start
				for end < lineEnd && source[end] == source[start] {
					end++
				}
				run := end - start
				if fence == 0 && run >= 3 &&
					(source[start] == '~' || !strings.Contains(source[end:lineEnd], "`")) {
					fence, fenceLength = source[start], run
					delimiter = 0
				} else if fence == source[start] && run >= fenceLength &&
					strings.Trim(source[end:lineEnd], " \t\r") == "" {
					fence = 0
					i = lineEnd + 1
					continue
				}
			}
			if fence != 0 || delimiter == 0 && indented {
				i = lineEnd + 1 // Block contents are shell text, not inline-span openers.
				continue
			}
		}
		if delimiter == 0 && strings.HasPrefix(source[i:], "<!--") {
			closing := strings.Index(source[i+4:], "-->")
			if closing < 0 {
				i = len(source)
			} else {
				i += 4 + closing + 3
			}
			continue
		}
		if delimiter == 0 && source[i] == '\\' && i+1 < stop {
			i += 2 // An escaped prose backtick cannot open a code span.
			continue
		}
		if source[i] != '`' {
			i++
			continue
		}
		end := i
		for end < stop && source[end] == '`' {
			end++
		}
		if delimiter == 0 {
			delimiter = end - i
		} else if delimiter == end-i {
			delimiter = 0
		}
		i = end
	}
	m.position, m.delimiter, m.fence, m.fenceLength = i, delimiter, fence, fenceLength
	return delimiter
}

// normalizeShellFields joins only adjacent literal fragments of advertised field words.
// Markdown delimiters end a word; expansions and unresolved quoting never establish a clean scan.
func normalizeShellFields(source string) (string, error) {
	letter := func(c byte) bool { return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == ',' }
	space := func(c byte) bool { return c == ' ' || c == '\t' || c == '\n' || c == '\r' }
	var output strings.Builder
	markdown := &markdownObserver{}
	position := 0
	for position < len(source) {
		relative := strings.Index(source[position:], "--json")
		if relative < 0 {
			output.WriteString(source[position:])
			break
		}
		flag := position + relative
		start := flag + len("--json")
		// A quoted flag is one argument, while a closing Markdown backtick is a boundary.
		if start < len(source) && (source[start] == '\'' || source[start] == '"') && flag > 0 && source[flag-1] == source[start] {
			start++
		}
		if start == len(source) || !(space(source[start]) || source[start] == '=' || source[start] == ',') {
			output.WriteString(source[position:start])
			position = start
			continue
		}
		separatorStart := start
		for start < len(source) && (space(source[start]) || source[start] == '=' || source[start] == ',') {
			start++
		}
		end := start
		var word strings.Builder
		for end < len(source) {
			c := source[end]
			if c == '$' {
				return "", fmt.Errorf("JSON field word contains unresolved expansion")
			}
			if c == '\\' {
				return "", fmt.Errorf("JSON field word contains an unresolved escape")
			}
			if letter(c) {
				word.WriteByte(c)
				end++
				continue
			}
			if c == '`' {
				separator := source[separatorStart:end]
				if word.Len() == 0 && strings.HasPrefix(source[end:], "```") &&
					strings.Contains(separator, "\n") && strings.Trim(separator, " \t\r\n") == "" {
					break // A following Markdown fence is not part of a field word.
				}
				closing := end
				for closing < len(source) && source[closing] == '`' {
					closing++
				}
				if delimiter := markdown.delimiterAt(source, flag); delimiter == 0 || closing-end != delimiter {
					return "", fmt.Errorf("JSON field word contains unresolved command substitution")
				}
				break // Close the Markdown span that opened before this command.
			}
			if c != '\'' && c != '"' {
				break
			}
			closing := strings.IndexByte(source[end+1:], c)
			if closing < 0 {
				line := strings.LastIndexByte(source[:flag], '\n') + 1
				if strings.Count(source[line:flag], string(c))%2 == 0 ||
					end+1 < len(source) && (letter(source[end+1]) || source[end+1] == '$') {
					return "", fmt.Errorf("JSON field quoting is incomplete")
				}
				break // A surrounding prose quote can close after the final field.
			}
			closing += end + 1
			fragment := source[end+1 : closing]
			literal := true
			for i := 0; i < len(fragment); i++ {
				literal = literal && letter(fragment[i])
			}
			if !literal {
				if strings.ContainsAny(fragment, "$`\\") {
					return "", fmt.Errorf("JSON field quoting contains unresolved expansion")
				}
				break // Ordinary prose outside the literal field word remains a boundary.
			}
			word.WriteString(fragment)
			end = closing + 1
		}
		output.WriteString(source[position:start])
		output.WriteString(word.String())
		position = end
	}
	return output.String(), nil
}

// run reads a bounded retained snapshot and publishes only complete decoded guidance.
func run() error {
	if len(os.Args) == 2 && os.Args[1] == "--shell-fields" {
		input, err := io.ReadAll(io.LimitReader(os.Stdin, (8<<20)+1))
		if err != nil || len(input) > 8<<20 {
			return fmt.Errorf("guidance text exceeds the complete observation budget")
		}
		text, err := normalizeShellFields(string(input))
		if err != nil {
			return err
		}
		_, err = io.WriteString(os.Stdout, text)
		return err
	}
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

// main reports incomplete observation with the guard's UNKNOWN exit code.
func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
}
