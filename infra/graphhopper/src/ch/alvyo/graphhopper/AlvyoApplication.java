package ch.alvyo.graphhopper;

import com.graphhopper.application.GraphHopperServerConfiguration;
import com.graphhopper.application.cli.ImportCommand;
import com.graphhopper.application.cli.MatchCommand;
import com.graphhopper.application.resources.RootResource;
import com.graphhopper.http.CORSFilter;
import com.graphhopper.http.GraphHopperBundle;
import com.graphhopper.navigation.NavigateResource;
import io.dropwizard.assets.AssetsBundle;
import io.dropwizard.core.Application;
import io.dropwizard.core.setup.Bootstrap;
import io.dropwizard.core.setup.Environment;
import jakarta.servlet.DispatcherType;

import java.util.EnumSet;

/**
 * GraphHopper's own application (GraphHopperApplication of 11.0, which is
 * final), with Alvyo's {@link ReachTreeResource} added.
 */
public final class AlvyoApplication extends Application<GraphHopperServerConfiguration> {

    public static void main(String[] args) throws Exception {
        new AlvyoApplication().run(args);
    }

    @Override
    public void initialize(Bootstrap<GraphHopperServerConfiguration> bootstrap) {
        bootstrap.addBundle(new GraphHopperBundle());
        bootstrap.addCommand(new ImportCommand());
        bootstrap.addCommand(new MatchCommand());
        bootstrap.addBundle(new AssetsBundle("/com/graphhopper/maps/", "/maps/", "index.html"));
        bootstrap.addBundle(new AssetsBundle("/META-INF/resources/webjars", "/webjars/", null, "webjars"));
    }

    @Override
    public void run(GraphHopperServerConfiguration configuration, Environment environment) {
        environment.jersey().register(new RootResource());
        environment.jersey().register(NavigateResource.class);
        environment.jersey().register(ReachTreeResource.class);
        environment.servlets().addFilter("cors", CORSFilter.class).addMappingForUrlPatterns(EnumSet.allOf(DispatcherType.class), false, "*");
    }
}
