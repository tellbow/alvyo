package routing

// wayType groups GraphHopper road classes for the way-type breakdown.
func wayType(roadClass string) string {
	switch roadClass {
	case "track":
		return "track"
	case "path", "footway", "bridleway", "cycleway", "corridor", "platform":
		return "path"
	case "steps":
		return "steps"
	case "":
		return "unknown"
	default:
		return "road"
	}
}

// isPath reports whether a road class is a footpath for SAC purposes.
// Unknown ways (straight-line legs drawn off the network) count as paths so
// that their grade is a cautious guess rather than "road".
func isPath(roadClass string) bool {
	switch roadClass {
	case "path", "footway", "bridleway", "steps", "":
		return true
	}
	return false
}

// surfaceGroup groups GraphHopper surfaces for the surface breakdown.
func surfaceGroup(surface string) string {
	switch surface {
	case "asphalt", "paved", "concrete", "paving_stones", "cobblestone":
		return "paved"
	case "compacted", "fine_gravel", "gravel", "unpaved":
		return "gravel"
	case "ground", "dirt", "grass", "sand", "wood":
		return "natural"
	default:
		return "unknown"
	}
}
