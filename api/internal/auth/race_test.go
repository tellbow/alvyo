//go:build race

package auth

// The race detector slows hashing about 14 times (1 s instead of 75 ms on
// the cluster's arm64 runners), so TestHashCost measures nothing under it.
const raceEnabled = true
