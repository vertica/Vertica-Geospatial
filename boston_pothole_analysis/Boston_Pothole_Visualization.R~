# R script for the Boston Potholes Blog post

#Load libraries
library(ggplot2)
library(ggmap)

# Read in the data
new_potholes = read.csv("heatmap.dat")

# Return the maps for different locations
downtown = get_map(location = "Boston, MA", zoom = 15)

# Create the heatmap
heat_map = ggmap(downtown) + geom_polygon(data = new_potholes, aes(y = Longitude, x = Latitude, group = gid,
                                                                   fill = Ratio), alpha = .7) +
                scale_fill_gradient(low = "light yellow", high = "red", guide = "legend", na.value="light yellow",
                                    limits = c(0,5), breaks = c(0.001,1,2,3,4,5))
# Plot the heatmap
heat_map + theme(panel.grid.major = element_blank(), panel.grid.minor = element_blank(), 
                     axis.ticks = element_blank(), axis.title = element_blank(), axis.text = element_blank())
