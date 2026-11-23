package review

import (
	"fmt"
	"html"
	"net/url"
	"path"
	"regexp"
	"slices"
	"sort"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
)

// The images a change commits, shown on its PR. A PR's page shows a committed
// image only in its Files tab, so the demo check posts each image the change
// adds, changes, moves or removes in comments of its own, a changed one before
// and after. Each image is drawn from the file the repository holds at a
// commit, at the address GitHub serves that file from, so the viewer's own
// session loads it, from a private repository too, and nothing is uploaded.
//
// A change is what a review reads: the diff from the merge base of its base
// and its head to its head. A before is the image at that merge base, and an
// after the image at the head.

// imageTypes are the extensions of the images a PR's page draws from a
// committed file, in any case.
var imageTypes = map[string]bool{"png": true, "jpg": true, "jpeg": true, "gif": true, "svg": true, "webp": true}

// isImage reports whether p names an image a PR's page draws.
func isImage(p string) bool {
	return imageTypes[strings.ToLower(strings.TrimPrefix(path.Ext(p), "."))]
}

// ImageKind is what a change does to one image.
type ImageKind int

const (
	// ImageAdded is an image the head holds and the merge base does not.
	ImageAdded ImageKind = iota + 1
	// ImageChanged is an image whose content the change alters, at its path
	// or at a path it moves the image to.
	ImageChanged
	// ImageRemoved is an image the merge base holds and the head does not.
	ImageRemoved
	// ImageMoved is an image the change moves without altering its content.
	ImageMoved
)

// Image is one image a change touches. Path is where the head holds it, and
// where the merge base held it when the change removes it. From is the path
// the merge base held it at when the change moves it, and "" otherwise.
type Image struct {
	Kind ImageKind
	Path string
	From string
}

// Images is what a change does to the images its repository holds.
type Images struct {
	// Head is the reviewed commit and MergeBase the commit the change
	// branches from, both full object names.
	Head, MergeBase string
	// Changes is each image the change touches, by path.
	Changes []Image
	// held is the names of the images in each directory that holds one the
	// change touches: those at the head, and those the change removes. Which
	// parts of a name vary is read across them.
	held map[string][]string
}

// ReadImages reads, in the clone dir sits in, what the change from the merge
// base of base and oid to oid does to the images it holds. A file is an image
// by its extension, and only a regular file is one, so a symlink is not.
// Changing only a file's mode changes no image. Git's rename detection says
// which image moved.
func ReadImages(dir, base, oid string) (Images, error) {
	head, err := commitOf(dir, "--oid", oid)
	if err != nil {
		return Images{}, err
	}
	from, err := commitOf(dir, "--base", base)
	if err != nil {
		return Images{}, err
	}
	mb, err := git.MergeBase(dir, from, head)
	if err != nil {
		return Images{}, fmt.Errorf("%s and %s share no merge base: %w", base, oid, err)
	}
	raw, err := git.Output(dir, "diff", "--raw", "-z", "-M", "--no-abbrev", "--no-relative", mb, head)
	if err != nil {
		return Images{}, err
	}
	entries, err := parseRaw(raw)
	if err != nil {
		return Images{}, err
	}
	im := Images{Head: head, MergeBase: mb}
	for _, e := range entries {
		if c, ok := e.image(); ok {
			im.Changes = append(im.Changes, c)
		}
	}
	sort.Slice(im.Changes, func(i, j int) bool { return im.Changes[i].Path < im.Changes[j].Path })
	if len(im.Changes) == 0 {
		return im, nil
	}
	tree, err := git.Output(dir, "ls-tree", "-r", "-z", "--full-tree", head)
	if err != nil {
		return Images{}, err
	}
	dirs := map[string]bool{}
	for _, c := range im.Changes {
		dirs[path.Dir(c.Path)] = true
	}
	im.held = map[string][]string{}
	hold := func(p string) {
		if d := path.Dir(p); dirs[d] && !slices.Contains(im.held[d], path.Base(p)) {
			im.held[d] = append(im.held[d], path.Base(p))
		}
	}
	for _, rec := range strings.Split(tree, "\x00") {
		meta, p, ok := strings.Cut(rec, "\t")
		if ok && regular(strings.Fields(meta)[0]) && isImage(p) {
			hold(p)
		}
	}
	for _, c := range im.Changes {
		hold(c.Path)
	}
	return im, nil
}

// commitOf is the full object name of the commit rev names, which flag gave.
func commitOf(dir, flag, rev string) (string, error) {
	out, err := git.Output(dir, "rev-parse", "--verify", "--quiet", rev+"^{commit}")
	id := strings.TrimSpace(out)
	if err != nil || id == "" {
		return "", fmt.Errorf("%s %q names no commit in %s", flag, rev, dir)
	}
	return id, nil
}

// rawEntry is one path of `git diff --raw -z`: the modes and blobs on each
// side, the status letter, and the path on each side, which differ for a move.
type rawEntry struct {
	oldMode, newMode, oldBlob, newBlob, status, src, dst string
}

func parseRaw(out string) ([]rawEntry, error) {
	fields := strings.Split(out, "\x00")
	var entries []rawEntry
	for i := 0; i < len(fields); {
		meta := fields[i]
		if meta == "" {
			i++
			continue
		}
		parts := strings.Fields(strings.TrimPrefix(meta, ":"))
		if !strings.HasPrefix(meta, ":") || len(parts) != 5 || i+1 >= len(fields) {
			return nil, fmt.Errorf("git diff --raw: an entry does not read: %q", meta)
		}
		e := rawEntry{oldMode: parts[0], newMode: parts[1], oldBlob: parts[2], newBlob: parts[3],
			status: parts[4][:1], src: fields[i+1]}
		e.dst, i = e.src, i+2
		if e.status == "R" || e.status == "C" {
			if i >= len(fields) {
				return nil, fmt.Errorf("git diff --raw: the move of %q names no path it lands at", e.src)
			}
			e.dst, i = fields[i], i+1
		}
		entries = append(entries, e)
	}
	return entries, nil
}

// regular reports whether a tree mode is a regular file's.
func regular(mode string) bool { return mode == "100644" || mode == "100755" }

// image is what the entry does to an image, and false when it touches none.
func (e rawEntry) image() (Image, bool) {
	before := regular(e.oldMode) && isImage(e.src)
	after := regular(e.newMode) && isImage(e.dst)
	switch {
	case before && after && e.oldBlob == e.newBlob && e.src == e.dst:
		return Image{}, false
	case before && after && e.oldBlob == e.newBlob:
		return Image{Kind: ImageMoved, Path: e.dst, From: e.src}, true
	case before && after && e.src != e.dst:
		return Image{Kind: ImageChanged, Path: e.dst, From: e.src}, true
	case before && after:
		return Image{Kind: ImageChanged, Path: e.dst}, true
	case after:
		return Image{Kind: ImageAdded, Path: e.dst}, true
	case before:
		return Image{Kind: ImageRemoved, Path: e.src}, true
	}
	return Image{}, false
}

// ImageGroup is the images a comment shows together: those in one directory
// whose names share a stem, the part left once the parts that vary across the
// directory's images drop, such as a theme, a device or a browser. A directory
// whose images share no stem is one group, with no stem.
type ImageGroup struct {
	Dir, Stem string
	Images    []Image
}

// maxVariants is the most values one part of a name takes and still varies
// as a theme, a device, a browser or a platform does, rather than naming what
// the image shows.
const maxVariants = 8

// namePart is one part of a file name, split at -, _, . and spaces, with where
// it starts in the name.
type namePart struct {
	text  string
	start int
}

var nameSep = regexp.MustCompile(`[-_. ]+`)

// nameParts splits a file name, less its extension, into its parts.
func nameParts(name string) (string, []namePart) {
	base := strings.TrimSuffix(name, path.Ext(name))
	var parts []namePart
	start := 0
	for _, m := range nameSep.FindAllStringIndex(base, -1) {
		if m[0] > start {
			parts = append(parts, namePart{base[start:m[0]], start})
		}
		start = m[1]
	}
	if start < len(base) {
		parts = append(parts, namePart{base[start:], start})
	}
	return base, parts
}

// variantParts is how many of the last parts of names vary across them: the
// most for which each such part takes at most maxVariants values, fewer values
// than there are names, and every name keeps a part before them.
func variantParts(names []string) int {
	split := make([][]namePart, len(names))
	shortest := -1
	for i, n := range names {
		_, split[i] = nameParts(n)
		if shortest < 0 || len(split[i]) < shortest {
			shortest = len(split[i])
		}
	}
	k := 0
	for k+1 < shortest {
		values := map[string]bool{}
		for _, parts := range split {
			values[strings.ToLower(parts[len(parts)-k-1].text)] = true
		}
		if len(values) > maxVariants || len(values) >= len(names) {
			break
		}
		k++
	}
	return k
}

// stem is a file name less its extension and its last k parts.
func stem(name string, k int) string {
	base, parts := nameParts(name)
	if k == 0 || len(parts) <= k {
		return base
	}
	return strings.TrimRight(base[:parts[len(parts)-k].start], "-_. ")
}

// Groups is the change's images by directory, and within a directory by
// stem, each in path order, the groups in order of directory and stem.
func (im Images) Groups() []ImageGroup {
	byDir := map[string][]Image{}
	for _, c := range im.Changes {
		d := path.Dir(c.Path)
		byDir[d] = append(byDir[d], c)
	}
	dirs := make([]string, 0, len(byDir))
	for d := range byDir {
		dirs = append(dirs, d)
	}
	sort.Strings(dirs)
	var groups []ImageGroup
	for _, d := range dirs {
		k := variantParts(im.held[d])
		byStem := map[string][]Image{}
		for _, c := range byDir[d] {
			s := stem(path.Base(c.Path), k)
			byStem[s] = append(byStem[s], c)
		}
		if len(byStem) == len(byDir[d]) {
			groups = append(groups, ImageGroup{Dir: d, Images: byDir[d]})
			continue
		}
		stems := make([]string, 0, len(byStem))
		for s := range byStem {
			stems = append(stems, s)
		}
		sort.Strings(stems)
		for _, s := range stems {
			groups = append(groups, ImageGroup{Dir: d, Stem: s, Images: byStem[s]})
		}
	}
	return groups
}

// commentLimit is the most GitHub takes in a comment's body, 65,536
// characters as its API reports it, counted here in bytes, which are never
// fewer, and commentRoom what a comment's groups may take of it, leaving room
// for its opening line and the city's mark.
const (
	commentLimit = 65536
	commentRoom  = commentLimit - 1024
)

// openRows is the most images a change shows, a changed one counted once,
// whose groups open on the page. A change that shows more opens none, so the
// page shows a line for each group, which a reader opens.
const openRows = 4

// imageWidth is the width each image is drawn at, in pixels, so that a before
// and an after fit side by side in a comment.
const imageWidth = 350

// ImageComments is the comments that show the change's images on the PR in
// repo, owner/name, on host: one or more, in order, each within GitHub's limit
// on a comment's length, and none when the change touches no image.
func (im Images) ImageComments(host, repo string) []string {
	return im.comments(host, repo, commentRoom)
}

func (im Images) comments(host, repo string, room int) []string {
	if len(im.Changes) == 0 {
		return nil
	}
	groups := im.Groups()
	rows := 0
	for _, c := range im.Changes {
		if c.Kind != ImageMoved {
			rows++
		}
	}
	open := rows <= openRows
	var blocks []string
	for _, g := range groups {
		blocks = append(blocks, im.groupBlocks(g, host, repo, open, room)...)
	}
	var bodies []string
	cur := ""
	for _, b := range blocks {
		if cur != "" && len(cur)+len(b) > room {
			bodies = append(bodies, cur)
			cur = ""
		}
		cur += b
	}
	bodies = append(bodies, cur)
	opening := im.opening(len(groups))
	for i := range bodies {
		place := ""
		if len(bodies) > 1 {
			place = fmt.Sprintf(" This is comment %d of %d.", i+1, len(bodies))
		}
		bodies[i] = opening + place + "\n\n" + bodies[i]
	}
	return bodies
}

// Counts names how many images the change touches of each kind, such as "8
// changed and 2 added".
func (im Images) Counts() string {
	n := map[ImageKind]int{}
	for _, c := range im.Changes {
		n[c.Kind]++
	}
	var parts []string
	for _, k := range []ImageKind{ImageChanged, ImageAdded, ImageRemoved, ImageMoved} {
		if n[k] > 0 {
			parts = append(parts, fmt.Sprintf("%d %s", n[k], k.word()))
		}
	}
	return joinList(parts)
}

func (k ImageKind) word() string {
	switch k {
	case ImageAdded:
		return "added"
	case ImageChanged:
		return "changed"
	case ImageRemoved:
		return "removed"
	case ImageMoved:
		return "moved"
	}
	return "touched"
}

func joinList(parts []string) string {
	switch len(parts) {
	case 0:
		return ""
	case 1:
		return parts[0]
	}
	return strings.Join(parts[:len(parts)-1], ", ") + " and " + parts[len(parts)-1]
}

// opening is the line each comment opens with.
func (im Images) opening(groups int) string {
	in := ""
	if groups > 1 {
		in = fmt.Sprintf(", in %d groups", groups)
	}
	return fmt.Sprintf("**Images in this change**, at %s: %s%s. A before is the image at %s, "+
		"the commit the change branches from, and an after the image at %s.",
		short(im.Head), im.Counts(), in, short(im.MergeBase), short(im.Head))
}

// groupBlocks renders a group as one block, or as several, each within room,
// when one would not fit in a comment. A block shows its images in a table,
// then names those moved without a change in a sentence.
func (im Images) groupBlocks(g ImageGroup, host, repo string, open bool, room int) []string {
	label := code(g.Dir + "/")
	if g.Dir == "." {
		label = "the repository's top directory"
	}
	if g.Stem != "" {
		label += " <b>" + escape(g.Stem) + "</b>"
	}
	head := fmt.Sprintf("| Before, at %s | After, at %s |\n|---|---|\n", short(im.MergeBase), short(im.Head))
	const movedLead, movedEnd, movedSep = "Moved without a change: ", ".\n\n", " and "
	// A block keeps room for its summary, at most a few hundred characters
	// beyond the group's label, its table's head and its sentence's ends. Its
	// items fill the rest, a moved image with the longest separator a list
	// puts beside it.
	type item struct {
		text  string
		moved bool
	}
	var items []item
	for _, c := range g.Images {
		if c.Kind != ImageMoved {
			items = append(items, item{text: im.row(c, host, repo)})
		}
	}
	for _, c := range g.Images {
		if c.Kind == ImageMoved {
			items = append(items, item{text: fmt.Sprintf("%s from %s", code(path.Base(c.Path)), code(c.From)), moved: true})
		}
	}
	fixed := 400 + len(label) + len(head) + len(movedLead) + len(movedEnd)
	var parts [][]item
	var cur []item
	size := fixed
	for _, it := range items {
		cost := len(it.text)
		if it.moved {
			cost += len(movedSep)
		}
		if len(cur) > 0 && size+cost > room {
			parts = append(parts, cur)
			cur, size = nil, fixed
		}
		cur = append(cur, it)
		size += cost
	}
	parts = append(parts, cur)
	attr := ""
	if open {
		attr = " open"
	}
	counts := (Images{Changes: g.Images}).Counts()
	var blocks []string
	for i, p := range parts {
		of := ""
		if len(parts) > 1 {
			of = fmt.Sprintf(", part %d of %d", i+1, len(parts))
		}
		var rows, moved []string
		for _, it := range p {
			if it.moved {
				moved = append(moved, it.text)
			} else {
				rows = append(rows, it.text)
			}
		}
		var b strings.Builder
		fmt.Fprintf(&b, "<details%s>\n<summary>%s · %s%s</summary>\n\n", attr, label, counts, of)
		if len(rows) > 0 {
			b.WriteString(head)
			b.WriteString(strings.Join(rows, ""))
			b.WriteString("\n")
		}
		if len(moved) > 0 {
			b.WriteString(movedLead + joinList(moved) + movedEnd)
		}
		b.WriteString("</details>\n\n")
		blocks = append(blocks, b.String())
	}
	return blocks
}

// row is an image's two rows of a group's table: its name, then its before
// and its after.
func (im Images) row(c Image, host, repo string) string {
	name := code(path.Base(c.Path))
	if c.From != "" {
		name += ", moved from " + code(c.From)
	}
	before, after := "*not in the base*", "*removed*"
	if c.Kind != ImageAdded {
		was := c.Path
		if c.From != "" {
			was = c.From
		}
		before = img(rawURL(host, repo, im.MergeBase, was), "before: "+was)
	}
	if c.Kind != ImageRemoved {
		after = img(rawURL(host, repo, im.Head, c.Path), "after: "+c.Path)
	}
	return fmt.Sprintf("| %s | |\n| %s | %s |\n", name, before, after)
}

// rawURL is the address GitHub serves the file p from, as repo holds it at
// commit.
func rawURL(host, repo, commit, p string) string {
	segs := strings.Split(p, "/")
	for i, s := range segs {
		segs[i] = url.PathEscape(s)
	}
	return "https://" + host + "/" + repo + "/raw/" + commit + "/" + strings.Join(segs, "/")
}

func img(src, alt string) string {
	return fmt.Sprintf(`<img src="%s" alt="%s" width="%d">`, escape(src), escape(alt), imageWidth)
}

func code(s string) string { return "<code>" + escape(s) + "</code>" }

// escape makes s HTML text, safe inside an attribute and in a table cell.
func escape(s string) string {
	return strings.ReplaceAll(html.EscapeString(s), "|", "&#124;")
}
