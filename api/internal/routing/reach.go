package routing

import (
	"context"
	"time"

	"github.com/tellbow/alvyo/swiss/geo"
)

// ReachHours are the hours «Wie weit komme ich?» shows, each as an area.
var ReachHours = []int{2, 4, 8}

// ReachArea is what one reaches from a point within Hours: its outline, the
// outer ring first, [lon, lat] per point.
type ReachArea struct {
	Hours   int            `json:"hours"`
	Outline [][][2]float64 `json:"outline" doc:"Polygon rings, the outer one first; [lon, lat] per point"`
}

// reachTimeout: eight hours on foot search much of a region (GraphHopper's
// shortest path tree about 2 s in production), more than a leg's 10 s.
const reachTimeout = 45 * time.Second

// Reach returns the areas reached from p within ReachHours at pace (one's
// time as a multiple of the Swiss hiking time), the smallest first.
// GraphHopper's shortest path tree over the time profiles (hike_time,
// alpine_time), timed by slope like the Swiss formula, gives every node's
// time from p; the paths within each limit are outlined as for ReachBack.
// Not GraphHopper's isochrones: they triangulate every node reached, about
// 10 s in production against 2 s for the tree.
func (r *Router) Reach(ctx context.Context, p geo.Point, profile string, pace float64) ([]ReachArea, error) {
	if pace <= 0 {
		pace = 1
	}
	most := float64(ReachHours[len(ReachHours)-1]) * 3600 / pace
	out, err := r.GraphHopper.spt(ctx, p, profile, most*overreach, false)
	if err != nil {
		return nil, err
	}
	return r.areas(ctx, pace, out, func(_ int64, ms float64) float64 { return ms })
}
