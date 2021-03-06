% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/read_acs1year.R
\name{read_acs1year}
\alias{read_acs1year}
\title{Read ACS 1-year estimates}
\usage{
read_acs1year(year, states, table_contents = NULL, areas = NULL,
  geo_headers = NULL, summary_level = "*", geo_comp = "total",
  with_margin = FALSE, with_acsgeoheaders = FALSE, show_progress = TRUE)
}
\arguments{
\item{year}{year of the estimate}

\item{states}{vector of state abbreviations, for example "IN" or c("MA", "RI").}

\item{table_contents}{selected references of contents in census tables. Users
can choose a name for each reference, such as in
c("abc = B01001_009", "fff = B00001_001").
Try to make names meaningful. To find the references of table contents
of interest, search with function \code{\link{search_tablecontents}}.}

\item{areas}{For metro area, in the format like "New York metro".
For county, city, or town, must use the exact name as those in
\code{\link{dict_fips}} in the format like "kent county, RI",
"Boston city, MA", and "Lincoln town, RI". And special examples like
"Salt Lake City city, UT" must keep the "city" after "City".}

\item{geo_headers}{vector of references of selected geographci headers to be
included in the return. Browse geoheaders in \code{\link{dict_acs_geoheader}}
or search with \code{\link{search_geoheaders}}}

\item{summary_level}{select which summary level to keep, "*" to keep all. It takes strings
including "state", "county", "county subdivision", "place", "tract", "block group",
and "block" for the most common levels. It also take code. Search all codes with
\code{\link{search_summarylevels}} or browse \code{\link{dict_acs_summarylevel}} .}

\item{geo_comp}{select which geographic component to keep, "*" to keep every geo-component,
"total" for "00", "urban" for "01", "urbanized area" for "04",
"urban cluster" for "28", "rural" for "43". Others should input code
which can be found with \code{\link{search_geocomponents}}. Availability
of geocomponent depends on summary level. State level contains all
geographic component. County subdivision and higher level have "00",
"01", and "43". Census tract and lower level have only "00".}

\item{with_margin}{read also margin of error in addition to estimate}

\item{with_acsgeoheaders}{whether to keep geographic headers from ACS data}

\item{show_progress}{whether to show progress in fread()}
}
\value{
A data.table of selected data.
}
\description{
This function retrieves data from summary file of ACS 1-year
estimates. In addition to selected geographic headers and table contents,
it also returns total population and coordinates of selected geographic
areas, as well as summary levels and geographic components.
}
\examples{
\dontrun{
# read summary data using areas of selected cities
aaa <- read_acs1year(
    year = 2016,
    states = c("UT", "RI"),
    table_contents = c("male = B01001_002", "female = B01001_026"),
    areas = c("Salt Lake City city, UT",
              "Providence city, RI",
              "PLACE = RI19180"),
    summary_level = "place",
    with_margin = TRUE
)


# read data using geoheaders - all major counties
bbb <- read_acs1year(
    year = 2015,
    states = c("UT", "RI"),
    table_contents = c("male = B01001_002", "female = B01001_026"),
    geo_headers = c("COUNTY"),
    summary_level = "county",
    with_margin = TRUE
)
}

}
