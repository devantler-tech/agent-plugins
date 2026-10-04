// Execute one filesystem operation in a pinned, symlink-free checkout directory.
// Go 1.22's File.Chdir keeps directory identity through a later ancestor rename.
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func enter(path string) (*os.File, error) {
	before, err := os.Lstat(path)
	if err != nil || !before.IsDir() {
		return nil, fmt.Errorf("parent is not a real directory: %s", path)
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	after, err := f.Stat()
	if err != nil || !os.SameFile(before, after) {
		f.Close()
		return nil, fmt.Errorf("parent moved while opening: %s", path)
	}
	if err = f.Chdir(); err != nil {
		f.Close()
		return nil, err
	}
	return f, nil
}

func run(args []string) error {
	if len(args) < 4 || args[2] != "--" || !filepath.IsAbs(args[0]) {
		return fmt.Errorf("expected absolute checkout root, relative parent, -- and command")
	}
	root, parent := args[0], args[1]
	if filepath.IsAbs(parent) || filepath.Clean(parent) != parent || parent == ".." || strings.HasPrefix(parent, "../") {
		return fmt.Errorf("parent escapes checkout")
	}
	// The process inherits the caller's already-pinned checkout cwd. Reopening
	// its absolute name would reintroduce races in ancestors of the checkout.
	paths := []string{"."}
	if parent != "." {
		paths = append(paths, strings.Split(parent, string(os.PathSeparator))...)
	}
	var dirs []*os.File
	defer func() {
		for _, d := range dirs {
			d.Close()
		}
	}()
	for _, path := range paths {
		d, err := enter(path)
		if err != nil {
			return err
		}
		dirs = append(dirs, d)
	}
	check := func() error {
		for i, d := range dirs {
			path := root
			if i > 0 {
				path = filepath.Join(root, filepath.Join(paths[1:i+1]...))
			}
			current, err := os.Lstat(path)
			pinned, statErr := d.Stat()
			if err != nil || statErr != nil || !current.IsDir() || !os.SameFile(current, pinned) {
				return fmt.Errorf("parent moved; recovery retained: %s", path)
			}
		}
		return nil
	}
	// Refuse before a cleanup side effect too: a post-only check would delete
	// originals in a moved checkout while reporting that they were retained.
	if err := check(); err != nil {
		return err
	}
	cmd := exec.Command(args[3], args[4:]...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		return err
	}
	// A successful write to an anchored directory does not publish a moved path.
	return check()
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		if child, ok := err.(*exec.ExitError); ok {
			os.Exit(child.ExitCode())
		}
		fmt.Fprintf(os.Stderr, "atomic-parent: %v\n", err)
		os.Exit(1)
	}
}
