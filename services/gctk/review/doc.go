// Package review is gctk's review domain (docs/gctk-architecture.md, "The
// surface"): the check index, which says which checks gate a change at a
// commit with the rig's index laid over the pack's, and the rig's guidance for
// each; and a review run's pass rule, its result and its asks
// (specs/tk-1tfzr71.108/design.md, sections 1 and 8).
//
// A review run is a root of the review formula, attached to the bead that owns
// a PR. Its steps write what they judged as their outputs, in the shapes
// run.go declares, and the domain reads only the store to judge them: Passed
// is the loop's check, Record writes the run's one result on the bead that
// owns the PR, review_results, which the domain owns and the pr evaluator reads
// through Results, and FileAsk files the asks the run works, whose checks the
// domain's review_checks names.
//
// For the demo check, ReadImages reads what a change does to the images its
// repository holds, and ImageComments renders the comments that show each one
// on its PR, a changed one before and after (images.go).
package review
