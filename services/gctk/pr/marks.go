package pr

// The city's two marks on a post, each a reaction of the account the city's gh
// token acts as, which the definition of feedback reads (gc_city_taken and
// gc_city_handled in assets/scripts/pr-post.sh). A post that carries either is
// one the city has taken. assets/scripts/pr-post.test.sh reads both names here.
const (
	// takenMark is the reaction the take leaves on a post once its ask is
	// filed: the city has the post and owes it an answer.
	takenMark = "EYES"
	// handledMark is the reaction the round's post leaves on a post once the
	// post's answer is on the PR: the city owes the post nothing more.
	handledMark = "THUMBS_UP"
)
