# package function =======================================================
#' Read ACS 1-year estimates
#'
#' @description This function retrieves data from summary file of ACS 1-year
#' estimates. In addition to selected geographic headers and table contents,
#' it also returns total population and coordinates of selected geographic
#' areas, as well as summary levels and geographic components.
#'
#' @param year  year of the estimate
#' @param states vector of state abbreviations, for example "IN" or c("MA", "RI").
#' @param table_contents selected references of contents in census tables. Users
#'        can choose a name for each reference, such as in
#'        c("abc = B01001_009", "fff = B00001_001").
#'        Try to make names meaningful. To find the references of table contents
#'        of interest, search with function \code{\link{search_tablecontents}}.
#' @param areas For metro area, in the format like "New York metro".
#'       For county, city, or town, must use the exact name as those in
#'       \code{\link{dict_fips}} in the format like "kent county, RI",
#'       "Boston city, MA", and "Lincoln town, RI". And special examples like
#'       "Salt Lake City city, UT" must keep the "city" after "City".
#' @param geo_headers vector of references of selected geographci headers to be
#'        included in the return. Browse geoheaders in \code{\link{dict_acs_geoheader}}
#'        or search with \code{\link{search_geoheaders}}
#' @param summary_level select which summary level to keep, "*" to keep all. It takes strings
#'        including "state", "county", "county subdivision", "place", "tract", "block group",
#'        and "block" for the most common levels. It also take code. Search all codes with
#'        \code{\link{search_summarylevels}} or browse \code{\link{dict_acs_summarylevel}} .
#' @param geo_comp select which geographic component to keep, "*" to keep every geo-component,
#'        "total" for "00", "urban" for "01", "urbanized area" for "04",
#'        "urban cluster" for "28", "rural" for "43". Others should input code
#'        which can be found with \code{\link{search_geocomponents}}. Availability
#'        of geocomponent depends on summary level. State level contains all
#'        geographic component. County subdivision and higher level have "00",
#'        "01", and "43". Census tract and lower level have only "00".
#' @param with_margin  read also margin of error in addition to estimate
#' @param with_acsgeoheaders whether to keep geographic headers from ACS data
#' @param show_progress  whether to show progress in fread()

#'
#' @return A data.table of selected data.
#'
#' @examples
#' \dontrun{
#' # read summary data using areas of selected cities
#' aaa <- read_acs1year(
#'     year = 2016,
#'     states = c("UT", "RI"),
#'     table_contents = c("male = B01001_002", "female = B01001_026"),
#'     areas = c("Salt Lake City city, UT",
#'               "Providence city, RI",
#'               "PLACE = RI19180"),
#'     summary_level = "place",
#'     with_margin = TRUE
#' )
#'
#'
#' # read data using geoheaders - all major counties
#' bbb <- read_acs1year(
#'     year = 2015,
#'     states = c("UT", "RI"),
#'     table_contents = c("male = B01001_002", "female = B01001_026"),
#'     geo_headers = c("COUNTY"),
#'     summary_level = "county",
#'     with_margin = TRUE
#' )
#' }
#'
#' @export
#'

read_acs1year <- function(year,
                          states,
                          table_contents = NULL,
                          areas = NULL,
                          geo_headers = NULL,
                          summary_level = "*",
                          geo_comp = "total",
                          with_margin = FALSE,
                          with_acsgeoheaders = FALSE,
                          show_progress = TRUE){

    # check if the path to census is set
    if (Sys.getenv("PATH_TO_CENSUS") == ""){
        message(paste(
            "Please set up the path to downloaded census data, following the instruction at",
            "https://github.com/GL-Li/totalcensus."
        ))
        return(NULL)
    }


     # allow lowerscase input
    states <- toupper(states)

    # check whether to download data
    path_to_census <- Sys.getenv("PATH_TO_CENSUS")

    # check if need to download generated data from census2010
    if (!file.exists(paste0(path_to_census, "/generated_data"))){
        download_generated_data()
    }


    # check whether to download census data
    not_downloaded <- c()
    for (st in states){
        # only check for this one file
        if (!file.exists(paste0(
            path_to_census, "/acs1year/", year, "/g", year, "1", tolower(st), ".csv"
        ))){
            not_downloaded <- c(not_downloaded, st)
        }
    }
    if (length(not_downloaded) > 0){
        cat(paste0(
            "Do you want to download ",
            year,
            " ACS 1-year survey summary files and save it to your computer? ",
            "It is necessary for extracting the data."
        ))
        continue <- switch(
            menu(c("yes", "no")),
            TRUE,
            FALSE
        )
        if (continue){
            download_census("acs1year", year)
        } else {
            stop("You choose not to download data.")
        }
    }

    if (is.null(areas) + is.null(geo_headers) == 0){
        stop("Must keep at least one of arguments areas and geo_headers NULL")
    }

    # add population to table contents so that it will never empty, remove it
    # from table_contents if "B01003_001" is included.
    if (any(grepl("B01003_001", table_contents))){
        message("B01003_001 is the population column.")
    }

    table_contents <- table_contents[!grepl("B01003_001", table_contents)]
    table_contents <- c("population = B01003_001", table_contents) %>%
        unique()

    content_names <- organize_tablecontents(table_contents) %>%
        .[, name]
    table_contents <- organize_tablecontents(table_contents) %>%
        .[, reference]

    # turn off warning, fread() gives warnings when read non-scii characters.
    options(warn = -1)

    if (!is.null(areas)){
        dt <- read_acs1year_areas_(
            year, states, table_contents, areas, summary_level, geo_comp,
            with_margin, with_acsgeoheaders, show_progress
        )
    } else {
        dt <- read_acs1year_geoheaders_(
            year, states, table_contents, geo_headers, summary_level, geo_comp,
            with_margin, with_acsgeoheaders, show_progress
        )
    }

    setnames(dt, table_contents, content_names)

    if (with_margin){
        setnames(dt, paste0(table_contents, "_m"), paste0(content_names, "_margin"))
    }

    options(warn = 0)
    return(dt)
}



# internal functions ===========================================================

read_acs1year_areas_ <- function(year,
                                 states,
                                 table_contents = NULL,
                                 areas = NULL,
                                 summary_level = "*",
                                 geo_comp = "*",
                                 with_margin = FALSE,
                                 with_acsgeoheaders = FALSE,
                                 show_progress = TRUE){
    # read ACS 1-year data of selected areas
    #
    # Args_____
    # year :  end year of the 5-year survey
    # states : vector of abbreviations of states such as c("MA", "RI")
    # table_contents :  vector of reference of available table contents
    # areas : For metro area, in the format like "New York metro".
    #      For county, city, or town, must use the exact name as those in
    #      \code{\link{dict_fips}} in the format like "kent county, RI",
    #     "Boston city, MA", and "Lincoln town, RI". And special examples like
    #     "Salt Lake City city, UT" must keep the "city" after "City".
    # summary_level : summary level like "050"
    # geo_comp : geographic component such as "00", "01", and "43"
    # with_margin : read also margin of error in addition to estimate
    # with_acsgeoheaders : whether to include geoheaders in ACS 1-year data
    # show_progress : whether to show progress in fread()n
    #
    # Return_____
    # A data.table
    #
    # Examples_____
    # aaa = read_acs1year_areas_(
    #     year = 2015,
    #     states = "ri",
    #     table_contents = "B01001_009",
    #     areas = c("Lincoln town, ri", "PLACE = RI59000", "providence metro"),
    #     summary_level = "county subdivision"
    # )
    #
    # bbb <- read_acs1year_areas_(
    #     year = 2015,
    #     states = c("ut", "ri"),
    #     table_contents = c("B01001_009", "B00001_001"),
    #     areas = c("Lincoln Town, RI",
    #               "Kent county, RI",
    #               "Salt Lake City city, UT",
    #               "Salt Lake metro",
    #               "Providence city, RI"),
    #     summary_level = "county subdivision"
    # )

    #=== prepare arguments ===

    # convert areas to the form of data.table
    #    geoheader  code state                    name
    # 1:     PLACE 62360    UT     Providence city, UT
    # 2:    COUNTY   005    RI      Newport County, RI
    dt_areas <- convert_areas(areas)


    states <- toupper(states)
    # toupper(NULL) ---> character(0) will cause trouble
    if (!is.null(table_contents)) table_contents <- toupper(table_contents)

    # this is used to extract geographic headers
    if (!is.null(areas)) geo_headers <- unique(dt_areas[, geoheader])

    # switch summary level to code
    summary_level <- switch_summarylevel(summary_level)
    geo_comp <- switch_geocomp(geo_comp)


    # lookup of the year
    lookup <- get(paste0("lookup_acs1year_", year))

    for (content in table_contents) {
        if (!tolower(content) %in% tolower(lookup$reference)){
            stop(paste("The table content reference", content, "does not exist."))
        }
    }

    # === read files ===

    lst_state <- list()
    for (st in states) {
        # read geography. do NOT read geo_headers from ACS data, instead read
        # from GEOID_coord_XX later on, which is generated from Census 2010 and
        # has much more geo_header data
        if (with_acsgeoheaders){
            geo <- read_acs1year_geo_(year, st, c(geo_headers, "STATE"),
                                      show_progress = show_progress) %>%
                # convert STATE fips to state abbreviation
                .[, state := convert_fips_to_names(STATE)] %>%
                setnames(geo_headers, paste0("acs_", geo_headers)) %>%
                setkey(LOGRECNO)
        }else {
            geo <- read_acs1year_geo_(year, st, "STATE",
                                      show_progress = show_progress) %>%
                # convert STATE fips to state abbreviation
                .[, state := convert_fips_to_names(STATE)] %>%
                setkey(LOGRECNO)
        }



        # read estimate and margin from each file
        if(!is.null(table_contents)){
            # get files for table contents, follow the notation of read_tablecontent.R
            dt <- read_acs1year_tablecontents_(year, st, table_contents,
                                               "e", show_progress)
            if (with_margin) {
                margin <- read_acs1year_tablecontents_(year, st, table_contents,
                                                       "m", show_progress)

                dt <- merge(dt, margin)
            }

            acs <- merge(geo, dt)
        } else {
            acs <- geo
        }

        # add coordinates
        acs <- add_coord(acs, st, geo_headers)

        lst_state[[st]] <- acs[SUMLEV %like% summary_level & GEOCOMP %like% geo_comp]

    }

    combined <- rbindlist(lst_state) %>%
        .[, ":=" (LOGRECNO = NULL, STATE = NULL)] %>%
        convert_geocomp_name() %>%
        # convert NA in state to nothing for selection below
        .[is.na(state), state := ""]

    if (!is.null(table_contents)){
        setnames(combined, paste0(table_contents, "_e"), table_contents)
    }


    # select data for argument geo_headers
    if (is.null(areas)) {
        selected <- combined
    } else {
        selected <- map(
            1:nrow(dt_areas),
            function(x) combined[get(dt_areas[x, geoheader]) %like% dt_areas[x, code] &
                                     state %like% dt_areas[x, state]] %>%
                .[, area := dt_areas[x, name]]
        ) %>%
            rbindlist() %>%
            # no use of the geoheaders
            .[, unique(dt_areas[, geoheader]) := NULL]
    }

    # reorder columns
    begin <- c("area", "GEOID", "lon", "lat", "state")
    end <- c("GEOCOMP", "SUMLEV", "NAME")
    if (with_margin){
        # estimate and margin together
        contents <- paste0(rep(table_contents, each = 2),
                           rep(c("", "_m"), length(table_contents)))
    } else {
        contents <- table_contents
    }
    setcolorder(selected, c(begin, contents, end))

    return(selected)
}




read_acs1year_geoheaders_ <- function(year,
                                      states,
                                      table_contents = NULL,
                                      geo_headers = NULL,
                                      summary_level = "*",
                                      geo_comp = "*",
                                      with_margin = FALSE,
                                      with_acsgeoheaders = FALSE,
                                      show_progress = TRUE){
    # read ACS 1-year data of selected geoheaders
    #
    # Args_____
    # year :  end year of the 5-year survey
    # states : vector of abbreviations of states such as c("MA", "RI")
    # table_contents :  vector of reference of available table contents
    # geo_headers : vector of geographic headers such as c("COUNTY", "PLACE").
    # summary_level : summary level like "050"
    # geo_comp : geographic component such as "00", "01", and "43"
    # with_margin : read also margin of error in addition to estimate
    # with_acsgeoheaders whether to include geographic headers from ACS data
    # show_progress : whether to show progress in fread()n
    #
    # Return_____
    # A data.table
    #
    # Examples_____
    # Area names are given when available if there is only one geoheader.
    # aaa = read_acs1year_geoheaders_(
    #     year = 2015,
    #     states = "ri",
    #     table_contents = "B01001_009",
    #     geo_headers = c("COUSUB"),
    #     summary_level = "county subdivision"
    # )
    #
    # No area names are given if there are multiple geoheaders.
    # bbb <- read_acs1year_geoheaders_(
    #     year = 2015,
    #     states = c("ut", "ri"),
    #     table_contents = c("B01001_009", "B00001_001"),
    #     geo_headers = c("PLACE"),
    #     summary_level = "place"
    # )

    #=== prepare arguments ===

    states <- toupper(states)
    # toupper(NULL) ---> character(0) will cause trouble
    if (!is.null(table_contents)) table_contents <- toupper(table_contents)

    # switch summary level to code when it is given as plain text
    summary_level <- switch_summarylevel(summary_level)
    geo_comp <- switch_geocomp(geo_comp)

    # lookup of the year
    lookup <- get(paste0("lookup_acs1year_", year))

    for (content in table_contents) {
        if (!tolower(content) %in% tolower(lookup$reference)){
            stop(paste("The table content reference", content, "does not exist."))
        }
    }

    # === read files ===

    lst_state <- list()
    for (st in states) {
        # read geography. do NOT read geo_headers from ACS data, instead read
        # from GEOID_coord_XX later on, which is generated from Census 2010 and
        # has much more geo_header data
        if (with_acsgeoheaders){
            geo <- read_acs1year_geo_(year, st, c(geo_headers, "STATE"),
                                      show_progress = show_progress) %>%
                # convert STATE fips to state abbreviation
                .[, state := convert_fips_to_names(STATE)] %>%
                setnames(geo_headers, paste0("acs_", geo_headers)) %>%
                setkey(LOGRECNO)
        }else {
            geo <- read_acs1year_geo_(year, st, "STATE",
                                      show_progress = show_progress) %>%
                # convert STATE fips to state abbreviation
                .[, state := convert_fips_to_names(STATE)] %>%
                .[, STATE := NULL] %>%
                setkey(LOGRECNO)
        }


        # read estimate and margin from each file
        if(!is.null(table_contents)){
            # get files for table contents, follow the notation of read_tablecontent.R
            dt <- read_acs1year_tablecontents_(year, st, table_contents,
                                               "e", show_progress)
            if (with_margin) {
                margin <- read_acs1year_tablecontents_(year, st, table_contents,
                                                       "m", show_progress)

                dt <- merge(dt, margin)
            }

            acs <- merge(geo, dt)
        } else {
            acs <- geo
        }

        # add coordinates and geoheaders from Census 2010 data
        acs <- add_coord(acs, st, geo_headers)


        lst_state[[st]] <- acs[SUMLEV %like% summary_level & GEOCOMP %like% geo_comp]

    }

    combined <- rbindlist(lst_state) %>%
        .[, LOGRECNO := NULL] %>%
        convert_geocomp_name()


    if (!is.null(table_contents)){
        setnames(combined, paste0(table_contents, "_e"), table_contents)
    }

    if (length(geo_headers) == 1 &&
        geo_headers %in% c("STATE", "COUNTY", "PLACE", "COUNTY", "CBSA", "COUSUB")){
        combined[, area := convert_fips_to_names(get(geo_headers), state, geo_headers, states)]
    }


    # reorder columns
    if (length(geo_headers) == 1 &&
        geo_headers %in% c("STATE", "COUNTY", "PLACE", "COUNTY", "CBSA", "COUSUB")){
        begin <- c("area", "GEOID", "lon", "lat", "state")
    } else {
        begin <- c("GEOID", "lon", "lat", "state")
    }
    end <- c("GEOCOMP", "SUMLEV", "NAME")

    if (with_margin){
        # estimate and margin together
        contents <- paste0(rep(table_contents, each = 2),
                           rep(c("", "_m"), length(table_contents)))
    } else {
        contents <- table_contents
    }
    setcolorder(combined, c(begin, geo_headers, contents, end))

    return(combined)
}






read_acs1year_geo_ <- function(year,
                               state,
                               geo_headers = NULL,
                               show_progress = TRUE) {
    # Read geography file of one state of ACS 1-year survey and return a
    # data.table of

    # Args_____
    # year : integer, year of 1-year census
    # state : string, state abbreviation such as "MA"
    # geo_headers : string vector of geographic headers such as c("PLACE", "CBSA")
    # show_progress : wheather to show the progress of fread()
    #
    # Return_____
    # a data.table with key of LOGRECNO


    #=== prepare arguments ===

    path_to_census <- Sys.getenv("PATH_TO_CENSUS")

    # allow lowercase input for state and geo_headers
    state <- tolower(state)
    geo_headers <- toupper(geo_headers) %>%
        unique()

    if (show_progress) {
        cat("Reading", toupper(state), year, "ACS 1-year survey geography file\n")
    }

    #=== read file ===

    file <- paste0(path_to_census, "/acs1year/", year, "/g", year, "1",
                   tolower(state), ".csv")

    if (year >= 2011){
        dict_geoheader <- dict_acs_geoheader
    } else if (year == 2010){
        dict_geoheader <- dict_acs_geoheader_2010
    }else if (year == 2009){
        dict_geoheader <- dict_acs_geoheader_2009_1year
    } else if (year >= 2006 & year <= 2008){
        dict_geoheader <- dict_acs_geoheader_2006_2008_1year
    } else if (year == 2005){
        dict_geoheader <- dict_acs_geoheader_2005_1year
    }

    # use "Latin-1" for encoding special spanish latters such as ñ in Cañada
    # read all columns and then select as the file is not as big as those in
    # decennial census.
    geo <- fread(file, header = FALSE, encoding = "Latin-1" ,
                 showProgress = show_progress, colClasses = "character") %>%
        setnames(dict_geoheader$reference) %>%
        .[, c(c("GEOID", "NAME", "LOGRECNO", "SUMLEV", "GEOCOMP"), geo_headers), with = FALSE] %>%
        .[, LOGRECNO := as.numeric(LOGRECNO)] %>%
        setkey(LOGRECNO)

    return(geo)
}




read_acs1year_1_file_tablecontents_ <- function(year, state, file_seg, table_contents,
                                                est_marg = "e", show_progress = TRUE){

    path_to_census <- Sys.getenv("PATH_TO_CENSUS")

    # get column names from file segment, then add six ommitted ones
    lookup <- get(paste0("lookup_acs1year_", year))
    col_names <- lookup[file_segment == file_seg] %>%
        # get rid of references ending with ".5", which are not in the file
        .[str_extract(reference, "..$") != ".5", reference]
    ommitted <- c("FILEID", "FILETYPE", "STUSAB", "CHARITER", "SEQUENCE", "LOGRECNO")
    col_names <- c(ommitted, col_names)

    file <- paste0(path_to_census, "/acs1year/", year, "/", est_marg, year, "1",
                   tolower(state), file_seg, "000.txt")

    dt <- fread(file, header = FALSE, showProgress = show_progress) %>%
        setnames(names(.), col_names) %>%
        .[, c("LOGRECNO", table_contents), with = FALSE] %>%
        # add "_e" or "_m" to show the data is estimate or margin
        setnames(table_contents, paste0(table_contents, "_", est_marg)) %>%
        setkey(LOGRECNO)

    # convert non-numeric columns to numeric
    # some missing data are denoted as ".", which lead to the whole column read
    # as character
    for (col in names(dt)){
        if (is.character(dt[, get(col)])){
            dt[, (col) := as.numeric(get(col))]
        }
    }

    return(dt)
}



# # example
# aaa <- read_acs1year_tablecontents_(
#     year = 2015,
#     state = "ri",
#     table_contents = c("B01001_009", "B00001_001", "B10001_002"),
#     est_marg = "m"
# )


read_acs1year_tablecontents_ <- function(year, state, table_contents,
                                         est_marg = "e",
                                         show_progress = TRUE){
    # Read ACS table_contents from 1-year survey and return a data.table
    #
    # Args_____
    # year: integer, year of the survey
    # state: state abbreviation
    # table_contents: vector of the table content references
    # est_marg: stringe, read estimate data or margin of error data, takes value
    #     "e" for estimate and "m" for margin of error
    # show_progress: wheather to show progress of fread()
    #
    # Return_____
    # a data table keyed with LOGRECNO
    #
    # Examples_____
    # table_contents = c("B01001_009", "B00001_001", "B10001_002")
    # read_acs1year_tablecontents_(2015, "RI", table_contents)



    # locate data files for the content
    lookup <- get(paste0("lookup_acs1year_", year))
    file_content <- lookup_tablecontents(table_contents, lookup)

    dt <- purrr::map2(file_content[, file_seg],
                      file_content[, table_contents],
                      function(x, y) read_acs1year_1_file_tablecontents_(
                          year, state, file_seg = x, table_contents = y,
                          est_marg = est_marg,
                          show_progress = show_progress
                      )) %>%
        purrr::reduce(merge, all = TRUE)

    return(dt)
}





