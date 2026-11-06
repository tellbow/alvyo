package ch.alvyo.graphhopper;

import com.graphhopper.GraphHopper;
import com.graphhopper.config.Profile;
import com.graphhopper.http.GHPointParam;
import com.graphhopper.http.ProfileResolver;
import com.graphhopper.isochrone.algorithm.ShortestPathTree;
import com.graphhopper.routing.ev.BooleanEncodedValue;
import com.graphhopper.routing.ev.Subnetwork;
import com.graphhopper.routing.querygraph.QueryGraph;
import com.graphhopper.routing.util.DefaultSnapFilter;
import com.graphhopper.routing.weighting.Weighting;
import com.graphhopper.storage.NodeAccess;
import com.graphhopper.storage.index.Snap;
import com.graphhopper.util.EdgeExplorer;
import com.graphhopper.util.EdgeIterator;
import com.graphhopper.util.FetchMode;
import com.graphhopper.util.GHUtility;
import com.graphhopper.util.Helper;
import com.graphhopper.util.PMap;
import com.graphhopper.util.Parameters;
import com.graphhopper.util.PointList;
import com.graphhopper.util.StopWatch;
import com.graphhopper.util.exceptions.PointNotFoundException;
import jakarta.inject.Inject;
import jakarta.validation.constraints.NotNull;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.StreamingOutput;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.BufferedWriter;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.io.UncheckedIOException;
import java.io.Writer;
import java.util.Locale;

import static com.graphhopper.routing.util.TraversalMode.EDGE_BASED;
import static com.graphhopper.routing.util.TraversalMode.NODE_BASED;

/**
 * GraphHopper's shortest path tree like /spt, but as every edge leaving a
 * node it reaches, with the edge's way: the reach areas follow the paths, not
 * straight lines between junctions (kilometres apart in the mountains), and
 * include the paths the tree itself never takes, whose ends are both reached
 * faster by others. CSV: from_node, to_node, time (ms, at to_node by this
 * edge), geometry ("lon lat" pairs joined by ";", from from_node to
 * to_node). The first row is the start: from_node -1, its own point.
 */
@Path("reach-tree")
public class ReachTreeResource {

    private static final Logger logger = LoggerFactory.getLogger(ReachTreeResource.class);

    private final GraphHopper graphHopper;
    private final ProfileResolver profileResolver;

    @Inject
    public ReachTreeResource(GraphHopper graphHopper, ProfileResolver profileResolver) {
        this.graphHopper = graphHopper;
        this.profileResolver = profileResolver;
    }

    @GET
    @Produces({"text/csv", "application/json"})
    public Response doGet(
            @QueryParam("profile") String profileName,
            @QueryParam("point") @NotNull GHPointParam point,
            @QueryParam("time_limit") @DefaultValue("600") long timeLimitInSeconds,
            @QueryParam("reverse_flow") @DefaultValue("false") boolean reverseFlow) {
        StopWatch sw = new StopWatch().start();
        PMap hints = new PMap();
        hints.putObject(Parameters.CH.DISABLE, true);
        hints.putObject(Parameters.Landmark.DISABLE, true);
        PMap resolverHints = new PMap(hints);
        resolverHints.putObject("profile", profileName);
        String name = profileResolver.resolveProfile(resolverHints);
        Profile profile = graphHopper.getProfile(name);
        if (profile == null)
            throw new IllegalArgumentException("The requested profile '" + name + "' does not exist");
        BooleanEncodedValue inSubnetwork = graphHopper.getEncodingManager().getBooleanEncodedValue(Subnetwork.key(name));
        Snap snap = graphHopper.getLocationIndex().findClosest(point.get().lat, point.get().lon, new DefaultSnapFilter(graphHopper.createWeighting(profile, hints), inSubnetwork));
        if (!snap.isValid())
            throw new PointNotFoundException("Point not found: " + point, 0);
        QueryGraph queryGraph = QueryGraph.create(graphHopper.getBaseGraph(), snap);
        NodeAccess nodeAccess = queryGraph.getNodeAccess();
        Weighting weighting = queryGraph.wrapWeighting(graphHopper.createWeighting(profile, hints));
        ShortestPathTree tree = new ShortestPathTree(queryGraph, weighting, reverseFlow,
                profile.hasTurnCosts() ? EDGE_BASED : NODE_BASED);
        tree.setTimeLimit(timeLimitInSeconds * 1000d);

        StreamingOutput out = output -> {
            try (Writer writer = new BufferedWriter(new OutputStreamWriter(output, Helper.UTF_CS))) {
                writer.write("from_node,to_node,time,geometry\n");
                writer.write("-1," + snap.getClosestNode() + ",0,");
                writer.write(point(nodeAccess.getLon(snap.getClosestNode()), nodeAccess.getLat(snap.getClosestNode())) + "\n");
                EdgeExplorer explorer = queryGraph.createEdgeExplorer();
                StringBuilder sb = new StringBuilder();
                tree.search(snap.getClosestNode(), label -> {
                    // as ShortestPathTree.search steps on from the label
                    EdgeIterator iter = explorer.setBaseNode(label.node);
                    while (iter.next()) {
                        if (iter.getEdge() == label.edge)
                            continue;
                        if (Double.isInfinite(GHUtility.calcWeightWithTurnWeight(weighting, iter, reverseFlow, label.edge)))
                            continue;
                        long time = label.time + GHUtility.calcMillisWithTurnMillis(weighting, iter, reverseFlow, label.edge);
                        sb.setLength(0);
                        sb.append(label.node).append(',').append(iter.getAdjNode()).append(',').append(time).append(',');
                        PointList way = iter.fetchWayGeometry(FetchMode.ALL);
                        for (int i = 0; i < way.size(); i++) {
                            if (i > 0)
                                sb.append(';');
                            sb.append(point(way.getLon(i), way.getLat(i)));
                        }
                        sb.append('\n');
                        try {
                            writer.write(sb.toString());
                        } catch (IOException e) {
                            throw new UncheckedIOException(e);
                        }
                    }
                });
            }
            logger.info("took: " + sw.stop().getSeconds() + ", visited nodes:" + tree.getVisitedNodes());
        };
        return Response.ok(out).type("text/csv").build();
    }

    // About a metre.
    private static String point(double lon, double lat) {
        return String.format(Locale.ROOT, "%.5f %.5f", lon, lat);
    }
}
