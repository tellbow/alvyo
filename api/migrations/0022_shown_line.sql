-- +goose Up
-- +goose StatementBegin
-- The line of a recorded hike as others see it: from the first point more
-- than 500 m from its start to the last point more than 500 m from its end
-- (routes.PrivacyM, Route.ForOthers); NULL when nothing is left.
CREATE FUNCTION shown_line(g geometry) RETURNS geometry
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
	WITH p AS (
		SELECT (d).path[1] AS i, (d).geom AS pt FROM ST_DumpPoints(g) d
	), b AS (
		SELECT min(i) FILTER (WHERE ST_DistanceSphere(pt, ST_StartPoint(g)) > 500) AS lo,
			max(i) FILTER (WHERE ST_DistanceSphere(pt, ST_EndPoint(g)) > 500) AS hi
		FROM p
	)
	SELECT ST_MakeLine(p.pt ORDER BY p.i) FROM p, b WHERE b.lo < b.hi AND p.i BETWEEN b.lo AND b.hi
$$;
-- +goose StatementEnd

-- +goose Down
DROP FUNCTION shown_line(geometry);
