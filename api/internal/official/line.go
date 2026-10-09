package official

import (
	"cmp"
	"container/heap"
	"math"
	"slices"

	"github.com/tellbow/alvyo/swiss/geo"
)

// Line joins the pieces of an official stage into one line. Wanderland
// keeps a stage as pieces that meet where paths branch, with small loops
// (round a station) and short side branches: without those, the line walks
// every piece once (a circuit, or from one end to the other with loops on
// the way). Where that cannot be, it is the longest of the shortest paths
// between two loose ends. Groups of pieces that do not meet are chained
// nearest end first.
func Line(parts [][]geo.Point) []geo.Point {
	line, _ := join(parts)
	return line
}

// jump joins the ends of two groups of pieces that do not meet.
type jump [2]geo.Point

// join is Line, also saying where it jumped from one group to the next.
func join(parts [][]geo.Point) ([]geo.Point, []jump) {
	var keep, rings [][]geo.Point
	for _, p := range parts {
		switch {
		case len(p) < 2:
		case p[0] == p[len(p)-1] && length(p) < smallLoopM:
			rings = append(rings, p)
		default:
			keep = append(keep, p)
		}
	}
	switch {
	case len(keep) == 0 && len(rings) > 0: // a short loop route
		return slices.MaxFunc(rings, func(a, b []geo.Point) int { return cmp.Compare(length(a), length(b)) }), nil
	case len(keep) == 0:
		return nil, nil
	case len(keep) == 1:
		return keep[0], nil
	}
	var lines [][]geo.Point
	for _, g := range groups(keep) {
		line := g[0]
		if len(g) > 1 {
			if line = eulerWalk(g); line == nil {
				if line = longestPath(g); line == nil {
					line, _ = chain(g)
				}
			}
		}
		lines = append(lines, line)
	}
	if len(lines) == 1 {
		return lines[0], nil
	}
	return chain(lines)
}

// split cuts a line where it jumps more than gap metres and keeps the parts
// of at least minM metres.
func split(line []geo.Point, jumps []jump, gap, minM float64) [][]geo.Point {
	isJump := map[jump]bool{}
	for _, j := range jumps {
		isJump[j], isJump[jump{j[1], j[0]}] = true, true
	}
	var parts [][]geo.Point
	start := 0
	for i := 1; i <= len(line); i++ {
		if i < len(line) && !(isJump[jump{line[i-1], line[i]}] && geo.Distance(line[i-1], line[i]) > gap) {
			continue
		}
		if p := line[start:i]; len(p) >= 2 && length(p) >= minM {
			parts = append(parts, p)
		}
		start = i
	}
	return parts
}

// groups splits the pieces into those that meet one another.
func groups(parts [][]geo.Point) [][][]geo.Point {
	parent := make([]int, len(parts))
	for i := range parent {
		parent[i] = i
	}
	var find func(int) int
	find = func(i int) int {
		if parent[i] != i {
			parent[i] = find(parent[i])
		}
		return parent[i]
	}
	at := map[geo.Point]int{}
	for i, p := range parts {
		for _, end := range []geo.Point{p[0], p[len(p)-1]} {
			if j, ok := at[end]; ok {
				parent[find(i)] = find(j)
			} else {
				at[end] = i
			}
		}
	}
	byRoot := map[int]int{}
	var out [][][]geo.Point
	for i, p := range parts {
		r := find(i)
		k, ok := byRoot[r]
		if !ok {
			k = len(out)
			byRoot[r] = k
			out = append(out, nil)
		}
		out[k] = append(out[k], p)
	}
	return out
}

// Loops round a station and branches to a viewpoint or a stop are left out
// up to these lengths.
const smallLoopM, spurM = 500, 300

// eulerWalk walks every piece once, without branches up to spurM off a
// junction: round a circuit, or from one odd end to the other. Nil when the
// pieces allow no such walk.
func eulerWalk(parts [][]geo.Point) []geo.Point {
	nodes := map[geo.Point]int{}
	node := func(p geo.Point) int {
		if i, ok := nodes[p]; ok {
			return i
		}
		nodes[p] = len(nodes)
		return nodes[p]
	}
	edges := make([]edge, len(parts))
	for i, p := range parts {
		edges[i] = edge{a: node(p[0]), b: node(p[len(p)-1]), m: length(p), pts: p}
	}
	alive := make([]bool, len(edges))
	degree := make([]int, len(nodes))
	adj := make([][]int, len(nodes))
	for i, e := range edges {
		alive[i] = true
		degree[e.a]++
		degree[e.b]++
		adj[e.a] = append(adj[e.a], i)
		if e.b != e.a {
			adj[e.b] = append(adj[e.b], i)
		}
	}
	// Short branches off a junction, again until none is left.
	for pruned := true; pruned; {
		pruned = false
		for i, e := range edges {
			if !alive[i] || e.a == e.b || e.m >= spurM {
				continue
			}
			if (degree[e.a] == 1 && degree[e.b] >= 3) || (degree[e.b] == 1 && degree[e.a] >= 3) {
				alive[i] = false
				degree[e.a]--
				degree[e.b]--
				pruned = true
			}
		}
	}
	var odd []int
	start := -1
	for n, d := range degree {
		if d%2 == 1 {
			odd = append(odd, n)
		}
		if d > 0 && start < 0 {
			start = n
		}
	}
	switch len(odd) {
	case 0:
	case 2:
		start = odd[0]
	default:
		return nil
	}
	if start < 0 {
		return nil
	}

	// Hierholzer: follow unused pieces; where none is left, the node joins
	// the walk (backwards).
	type step struct{ node, edge int }
	used := make([]bool, len(edges))
	next := make([]int, len(nodes))
	stack := []step{{start, -1}}
	var walk []step
	for len(stack) > 0 {
		top := stack[len(stack)-1]
		moved := false
		for next[top.node] < len(adj[top.node]) {
			i := adj[top.node][next[top.node]]
			next[top.node]++
			if used[i] || !alive[i] {
				continue
			}
			used[i] = true
			to := edges[i].b
			if to == top.node {
				to = edges[i].a
			}
			stack = append(stack, step{to, i})
			moved = true
			break
		}
		if !moved {
			walk = append(walk, top)
			stack = stack[:len(stack)-1]
		}
	}
	for i := range edges {
		if alive[i] && !used[i] {
			return nil
		}
	}
	slices.Reverse(walk)
	var line []geo.Point
	at := walk[0].node
	for _, st := range walk[1:] {
		e := edges[st.edge]
		pts := e.pts
		if e.a != at {
			pts = reversed(pts)
		}
		if len(line) > 0 {
			pts = pts[1:]
		}
		line = append(line, pts...)
		at = st.node
	}
	return line
}

// edge is a piece between two nodes (indexes of its end points).
type edge struct {
	a, b int
	m    float64
	pts  []geo.Point
}

// longestPath is the longest of the shortest paths between two dead ends
// of the network the pieces form.
func longestPath(parts [][]geo.Point) []geo.Point {
	nodes := map[geo.Point]int{}
	node := func(p geo.Point) int {
		if i, ok := nodes[p]; ok {
			return i
		}
		nodes[p] = len(nodes)
		return nodes[p]
	}
	edges := make([]edge, len(parts))
	for i, p := range parts {
		edges[i] = edge{a: node(p[0]), b: node(p[len(p)-1]), m: length(p), pts: p}
	}
	adj := make([][]int, len(nodes))
	for i, e := range edges {
		adj[e.a] = append(adj[e.a], i)
		adj[e.b] = append(adj[e.b], i)
	}
	var ends []int
	for n, es := range adj {
		if len(es) == 1 {
			ends = append(ends, n)
		}
	}
	best, from, to := -1.0, -1, -1
	var bestVia []int
	for _, s := range ends {
		dist, via := shortest(len(nodes), adj, edges, s)
		for _, t := range ends {
			if t != s && !math.IsInf(dist[t], 1) && dist[t] > best {
				best, from, to, bestVia = dist[t], s, t, via
			}
		}
	}
	if from < 0 {
		return nil
	}
	// Walk back from to, then turn the pieces around where needed.
	var path []int
	for n := to; n != from; {
		e := edges[bestVia[n]]
		path = append(path, bestVia[n])
		if e.a == n {
			n = e.b
		} else {
			n = e.a
		}
	}
	slices.Reverse(path)
	var line []geo.Point
	at := from
	for _, i := range path {
		e := edges[i]
		pts := e.pts
		if e.a != at {
			pts = reversed(pts)
			at = e.a
		} else {
			at = e.b
		}
		if len(line) > 0 {
			pts = pts[1:]
		}
		line = append(line, pts...)
	}
	return line
}

// shortest is Dijkstra from s: the distance to every node and the edge it
// is reached by.
func shortest(n int, adj [][]int, edges []edge, s int) ([]float64, []int) {
	dist := make([]float64, n)
	via := make([]int, n)
	for i := range dist {
		dist[i] = math.Inf(1)
		via[i] = -1
	}
	dist[s] = 0
	q := &queue{{s, 0}}
	for q.Len() > 0 {
		cur := heap.Pop(q).(visit)
		if cur.d > dist[cur.n] {
			continue
		}
		for _, i := range adj[cur.n] {
			e := edges[i]
			next := e.a
			if next == cur.n {
				next = e.b
			}
			if d := cur.d + e.m; d < dist[next] {
				dist[next], via[next] = d, i
				heap.Push(q, visit{next, d})
			}
		}
	}
	return dist, via
}

// visit is a node reached at distance d.
type visit struct {
	n int
	d float64
}

type queue []visit

func (q queue) Len() int           { return len(q) }
func (q queue) Less(i, j int) bool { return q[i].d < q[j].d }
func (q queue) Swap(i, j int)      { q[i], q[j] = q[j], q[i] }
func (q *queue) Push(x any)        { *q = append(*q, x.(visit)) }
func (q *queue) Pop() any {
	old := *q
	it := old[len(old)-1]
	*q = old[:len(old)-1]
	return it
}

// chain starts with the longest piece and adds the piece nearest to either
// end until none is left; jumps are where pieces did not meet.
func chain(parts [][]geo.Point) ([]geo.Point, []jump) {
	rest := slices.Clone(parts)
	i := 0
	for k, p := range rest {
		if length(p) > length(rest[i]) {
			i = k
		}
	}
	line := slices.Clone(rest[i])
	rest = slices.Delete(rest, i, i+1)
	var jumps []jump
	for len(rest) > 0 {
		bestK, bestD, atEnd, flip := 0, math.Inf(1), true, false
		for k, p := range rest {
			for _, c := range []struct {
				d         float64
				end, flip bool
			}{
				{geo.Distance(line[len(line)-1], p[0]), true, false},
				{geo.Distance(line[len(line)-1], p[len(p)-1]), true, true},
				{geo.Distance(line[0], p[len(p)-1]), false, false},
				{geo.Distance(line[0], p[0]), false, true},
			} {
				if c.d < bestD {
					bestK, bestD, atEnd, flip = k, c.d, c.end, c.flip
				}
			}
		}
		p := rest[bestK]
		if flip {
			p = reversed(p)
		}
		if bestD > 0 {
			if atEnd {
				jumps = append(jumps, jump{line[len(line)-1], p[0]})
			} else {
				jumps = append(jumps, jump{p[len(p)-1], line[0]})
			}
		}
		if atEnd {
			line = append(line, p...)
		} else {
			line = append(slices.Clone(p), line...)
		}
		rest = slices.Delete(rest, bestK, bestK+1)
	}
	return line, jumps
}

// Orient turns the lines of a route's stages so that each ends where the
// next one starts (the data does not keep the direction of a piece).
func Orient(lines [][]geo.Point) {
	near := func(p geo.Point, l []geo.Point) float64 {
		return math.Min(geo.Distance(p, l[0]), geo.Distance(p, l[len(l)-1]))
	}
	for i, l := range lines {
		if len(l) < 2 {
			continue
		}
		switch {
		case i+1 < len(lines) && len(lines[i+1]) >= 2:
			if next := lines[i+1]; near(l[0], next) < near(l[len(l)-1], next) {
				slices.Reverse(l)
			}
		case i > 0 && len(lines[i-1]) >= 2:
			if prev := lines[i-1]; geo.Distance(prev[len(prev)-1], l[len(l)-1]) < geo.Distance(prev[len(prev)-1], l[0]) {
				slices.Reverse(l)
			}
		}
	}
}

func length(p []geo.Point) float64 {
	m := 0.0
	for i := 1; i < len(p); i++ {
		m += geo.Distance(p[i-1], p[i])
	}
	return m
}

func reversed(p []geo.Point) []geo.Point {
	r := slices.Clone(p)
	slices.Reverse(r)
	return r
}
