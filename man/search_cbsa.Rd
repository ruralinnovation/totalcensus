% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/search_fips_cbsa.R
\name{search_cbsa}
\alias{search_cbsa}
\title{Search CBSA code and title}
\usage{
search_cbsa(keyword = "*", view = TRUE)
}
\arguments{
\item{keyword}{keyword to be searched in CBSA or CBSA title.}

\item{view}{display the search result with View if TRUE.}
}
\value{
A data.table
}
\description{
Search CBSA code of Core Based Statistical Area in dataset \code{\link{dict_cbsa}}.
The search also returns which CSA (Combined Statistical Area) that contains
the CBSA. If the CBSA contains multiple counties, each county is returned as
a row.
}
\details{
Quite often, multiple rows are returned. It is necessary
to hand pick the right one you are really looking for.
}
\examples{
# Change view = TRUE (default) to View the returned data.
aaa <- search_cbsa("providence", view = FALSE)

bbb <- search_cbsa("new york", view = FALSE)

\dontrun{
  # view all CBSA code
  search_cbsa()
}


}
