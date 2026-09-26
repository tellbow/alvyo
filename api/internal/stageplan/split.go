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
}

// Days asks for the number of days, or for days of a target length.
type Days struct {
	N       int     // number of days; 0 to follow TargetS
	TargetS float64 // hiking time per day; with N, the whole divided by N
	MaxS    float64 // no day longer, if at all possible; 0: 1.25 × target
}

// Costs: a day's squared relative deviation from the target, plus this for
// ending at a place of a kind not asked for.
const otherKindCost = 0.05

// overMaxCost makes days over the maximum a last resort, taken only when
// the number of days asked for cannot be met otherwise.
const overMaxCost = 100

// ErrNoDays means the request makes no sense (no days, no target).
var ErrNoDays = errors.New("stageplan: give the number of days or the hours per day")

// Split picks the places the days end at, as indexes into cands (sorted by
// Index), for a line with the hiking time secs at each vertex. Each day's
// time counts the way to the place in the evening and back in the morning.
func Split(secs []float64, cands []Candidate, d Days) ([]int, error) {
	total := secs[len(secs)-1]
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
	// Node 0 is the start, 1…len(cands) the places, last the end.
	n := len(cands) + 2
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
	cost := func(i, j int) float64 {
		a, da := at(i)
		b, db := at(j)
		if b <= a {
			return math.Inf(1)
		}
		day := secs[b] - secs[a] + da + db
		dev := (day - target) / target
		c := dev * dev
		if day > maxS {
			c += overMaxCost
		}
		if j < n-1 && !cands[j-1].Preferred {
			c += otherKindCost
		}
		return c
	}

	if d.N > 0 {
		return splitN(n, d.N, cost)
	}
	return splitFree(n, cost)
}

// splitN: best[k][j] is the cheapest way to reach node j at the end of day k.
func splitN(n, days int, cost func(i, j int) float64) ([]int, error) {
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
	return ends, nil
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
