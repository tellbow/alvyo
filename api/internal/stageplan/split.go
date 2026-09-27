package stageplan

import (
	"errors"
	"math"
)

// Candidate is a place a day can end at.
type Candidate struct {
	Index     int     // the vertex of the line nearest to the place
	DetourS   float64 // from the line to the place, one way
	Preferred bool    // of a kind the hiker asked for
	Shared    bool    // a night of another suggestion: one can change ways there
}

// Days asks for the number of days, for days of a target length, or for
// days between a least and a most.
type Days struct {
	N       int     // number of days; 0 to follow TargetS or the range
	TargetS float64 // hiking time per day; with N, the whole divided by N
	// MinS: with MaxS and neither N nor TargetS, as few days as fit
	// between the two.
	MinS float64
	MaxS float64 // no day longer, if at all possible; 0: 1.25 × target
}

// IsRange tells whether the days are asked for as a least and a most.
func (d Days) IsRange() bool { return d.N == 0 && d.TargetS == 0 && d.MinS > 0 && d.MaxS >= d.MinS }

// Costs: a day's squared relative deviation from the target, plus this for
// ending at a place of a kind not asked for.
const otherKindCost = 0.05

// sharedBonus favours a night another suggestion has too, but less than
// the kind asked for.
const sharedBonus = 0.03

// overMaxCost makes days over the maximum a last resort, taken only when
// the number of days asked for cannot be met otherwise; underMinCost the
// same for days under the least, which are the lesser evil.
const (
	overMaxCost  = 100
	underMinCost = 10
)

// maxRangeDays: of a range, at most this many numbers of days are tried.
const maxRangeDays = 30

// ErrNoDays means the request makes no sense (no days, no target).
var ErrNoDays = errors.New("stageplan: give the number of days or the hours per day")

// Split picks the places the days end at, as indexes into cands (sorted by
// Index), for a line with the hiking time secs at each vertex. Each day's
// time counts the way to the place in the evening and back in the morning.
func Split(secs []float64, cands []Candidate, d Days) ([]int, error) {
	total := secs[len(secs)-1]
	if d.IsRange() {
		return splitRange(secs, cands, d), nil
	}
	target := d.TargetS
	if d.N > 0 {
		target = total / float64(d.N)
	}
	if target <= 0 || d.N < 0 {
		return nil, ErrNoDays
	}
	maxS := d.MaxS
	if maxS <= 0 {
		maxS = math.Max(1.25*target, target+3600)
	}
	n, _, cost := costs(secs, cands, target, 0, maxS)
	if d.N > 0 {
		ends, _ := splitN(n, d.N, cost)
		return ends, nil
	}
	return splitFree(n, cost)
}

// splitRange takes as few days as fit between d.MinS and d.MaxS, each
// close to the whole divided by their number; if no number of days fits,
// the one that comes closest.
func splitRange(secs []float64, cands []Candidate, d Days) []int {
	total := secs[len(secs)-1]
	lo := max(1, int(math.Ceil(total/d.MaxS)))
	hi := min(max(lo, int(total/d.MinS)), lo+maxRangeDays-1)
	var best []int
	bestCost := math.Inf(1)
	for days := lo; days <= hi; days++ {
		n, day, cost := costs(secs, cands, total/float64(days), d.MinS, d.MaxS)
		ends, c := splitN(n, days, cost)
		fits := true
		prev := 0
		for _, j := range append(nodes(ends), n-1) {
			if t := day(prev, j); t < d.MinS || t > d.MaxS {
				fits = false
			}
			prev = j
		}
		if fits {
			return ends
		}
		if c < bestCost {
			best, bestCost = ends, c
		}
	}
	return best
}

// Fewest is the fewest days that keep every day at most maxS long, ending
// at cands; 0 if no split does (too few places to sleep).
func Fewest(secs []float64, cands []Candidate, maxS float64) int {
	n, day, _ := costs(secs, cands, 1, 0, maxS)
	// least[j]: the fewest days to reach node j.
	least := make([]int, n)
	for j := 1; j < n; j++ {
		for i := 0; i < j; i++ {
			if (i == 0 || least[i] > 0) && day(i, j) <= maxS && (least[j] == 0 || least[i]+1 < least[j]) {
				least[j] = least[i] + 1
			}
		}
	}
	return least[n-1]
}

// nodes turns indexes into cands into nodes of the split.
func nodes(ends []int) []int {
	out := make([]int, len(ends))
	for i, e := range ends {
		out[i] = e + 1
	}
	return out
}

// costs gives the nodes of a split (0 the start, 1…len(cands) the places,
// the last the end), a day's hiking time from node i to node j, and its
// cost.
func costs(secs []float64, cands []Candidate, target, minS, maxS float64) (n int, day, cost func(i, j int) float64) {
	n = len(cands) + 2
	at := func(i int) (index int, detour float64) {
		switch i {
		case 0:
			return 0, 0
		case n - 1:
			return len(secs) - 1, 0
		}
		c := cands[i-1]
		return c.Index, c.DetourS
	}
	day = func(i, j int) float64 {
		a, da := at(i)
		b, db := at(j)
		if b <= a {
			return math.Inf(1)
		}
		return secs[b] - secs[a] + da + db
	}
	cost = func(i, j int) float64 {
		t := day(i, j)
		if math.IsInf(t, 1) {
			return t
		}
		dev := (t - target) / target
		c := dev * dev
		if t > maxS {
			c += overMaxCost
		}
		if t < minS {
			c += underMinCost
		}
		if j < n-1 && !cands[j-1].Preferred {
			c += otherKindCost
		}
		if j < n-1 && cands[j-1].Shared {
			c -= sharedBonus
		}
		return c
	}
	return n, day, cost
}

// splitN: best[k][j] is the cheapest way to reach node j at the end of day k.
func splitN(n, days int, cost func(i, j int) float64) ([]int, float64) {
	if days > n-1 {
		days = n - 1 // fewer places than nights: as many days as possible
	}
	best := make([][]float64, days+1)
	from := make([][]int, days+1)
	for k := range best {
		best[k] = make([]float64, n)
		from[k] = make([]int, n)
		for j := range best[k] {
			best[k][j] = math.Inf(1)
		}
	}
	best[0][0] = 0
	for k := 1; k <= days; k++ {
		for j := 1; j < n; j++ {
			if (k < days) == (j == n-1) {
				continue // only the last day reaches the end
			}
			for i := 0; i < j; i++ {
				if c := best[k-1][i] + cost(i, j); c < best[k][j] {
					best[k][j], from[k][j] = c, i
				}
			}
		}
	}
	if math.IsInf(best[days][n-1], 1) && days > 1 {
		// Not enough places in order along the line (e.g. only at the
		// start or the end): one day fewer.
		return splitN(n, days-1, cost)
	}
	var ends []int
	for k, j := days, n-1; k > 1; k-- {
		j = from[k][j]
		ends = append([]int{j - 1}, ends...)
	}
	return ends, best[days][n-1]
}

// splitFree: best[j] is the cheapest way to reach node j, in any number of
// days.
func splitFree(n int, cost func(i, j int) float64) ([]int, error) {
	best := make([]float64, n)
	from := make([]int, n)
	for j := 1; j < n; j++ {
		best[j] = math.Inf(1)
		for i := 0; i < j; i++ {
			if c := best[i] + cost(i, j); c < best[j] {
				best[j], from[j] = c, i
			}
		}
	}
	var ends []int
	for j := from[n-1]; j > 0; j = from[j] {
		ends = append([]int{j - 1}, ends...)
	}
	return ends, nil
}
