# package function =======================================================
#' Read ACS 5-year estimates
#'
#' @description This function retrieves data from summary file of ACS 5-year
#' estimates. In addition to selected geographic headers and table contents,
#' it also returns total population and coordinates of selected geographic
#' areas, as well as summary levels and geographic components.
#'
#' @param year  end year of the 5-year estimate
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
#'        included in the return, like "COUNTY" or c("PLACE", "CBSA"). Browse
#'        geoheaders in \code{\link{dict_acs_geoheader}}
#'        or search with \code{\link{search_geoheaders}}
#' @param summary_level select which summary level to keep, "*" to keep all. It takes string
#'        including "state", "county", "county subdivision", "place", "tract", "block group",
#'        and "block" for the most common levels. It also take code. Search all codes with
#'        \code{\link{search_summarylevels}} or browse \code{\link{dict_acs_summarylevel}} .
#' @param geo_comp select which geographic component to keep, "*" to keep every component,
#'        "total" for "00", "urban" for "01", "urbanized area" for "04",
#'        "urban cluster" for "28", "rural" for "43". Others should be input as code
#'        which can be found with \code{\link{search_geocomponents}}. Availability
#'        of geocomponent depends on summary level. State level contains all
#'        geographic component. County subdivision and higher level have "00",
#'        "01", and "43". Census tract and lower level have only "00".
#' @param with_margin  read also margin of error in addition to estimate if TRUE
#' @param with_acsgeoheaders whether to keep geographic headers from ACS data
#' @param show_progress  whether to show progress in fread()
#'
#' @return A data.table of selected data.
#'
#' @examples
#' \dontrun{
#' # read data using areas
#' aaa <- read_acs5year(
#'     year = 2015,
#'     states = c("UT", "RI"),
#'     table_contents = c(
#'         "white = B02001_002",
#'         "black = B02001_003",
#'         "asian = B02001_005"
#'     ),
#'     areas = c(
#'         "Lincoln town, RI",
#'         "Salt Lake City city, UT",
#'         "Salt Lake City metro",
#'         "Kent county, RI",
#'         "COUNTY = UT001",
#'         "PLACE = UT62360"
#'     ),
#'     summary_level = "block group",
#'     with_margin = TRUE
#' )
#'
#'
#'# read data using geoheaders
#' bbb <- read_acs5year(
#'     year = 2015,
#'     states = c("UT", "RI"),
#'     table_contents = c("male = B01001_002", "female = B01001_026"),
#'     geo_headers = "PLACE",
#'     summary_level = "block group"
#' )
#'}
#'
#' @export
#'

read_acs5year <- function(year,
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
            path_to_census, "/acs5year/", year, "/g", year, "5", tolower(st), ".csv"
        ))){
            not_downloaded <- c(not_downloaded, st)
        }
    }
    if (length(not_downloaded) > 0){
        cat(paste0(
            "Do you want to download ",
            year,
            " ACS 5-year survey summary files of states ",
            paste0(not_downloaded, collapse = ", "),
            " and save it to your computer? It is necessary for extracting the data."
        ))
        continue <- switch(
            menu(c("yes", "no")),
            TRUE,
            FALSE
        )
        if (continue){
            download_census("acs5year", year, not_downloaded)
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
        dt <- read_acs5year_areas_(
            year, states, table_contents, areas, summary_level, geo_comp,
            with_margin, with_acsgeoheaders, show_progress
        )
    } else {
        dt <- read_acs5year_geoheaders_(
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





# internal functions ===============================================
read_acs5year_areas_ <- function(year,
                                 states,
                                 table_contents = NULL,
                                 areas = NULL,
                                 summary_level = "*",
                                 geo_comp = "*",
                                 with_margin = FALSE,
                                 with_acsgeoheaders = FALSE,
                                 show_progress = TRUE){
    # read ACS 5-year data of selected areas
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
    # with_acsgeoheaders whether to include geographic headers from ACS data
    # show_progress : whether to show progress in fread()n
    #
    # Return_____
    # A data.table
    #
    # Examples_____
    # aaa = read_acs5year_areas_(
    #     year = 2015,
    #     states = "ri",
    #     table_contents = "B01001_009",
    #     areas = c("Lincoln town, ri", "PLACE = RI59000", "providence metro"),
    #     summary_level = "block group"
    # )
    #
    # bbb <- read_acs5year_areas_(
    #     year = 2015,
    #     states = c("ut", "ri"),
    #     table_contents = c("B01001_009", "B00001_001"),
    #     areas = c("Lincoln Town, RI",
    #               "Kent county, RI",
    #               "Salt Lake City city, UT",
    #               "Salt Lake metro",
    #               "Providence city, RI"),
    #     summary_level = "block group"
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
    lookup <- get(paste0("lookup_acs5year_", year))

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
            geo <- read_acs5year_geo_(year, st, c(geo_headers, "STATE"),
                                      show_progress = show_progress) %>%
                # convert STATE fips to state abbreviation
                .[, state := convert_fips_to_names(STATE)] %>%
                setnames(geo_headers, paste0("acs_", geo_headers)) %>%
                setkey(LOGRECNO)
        }else {
            geo <- read_acs5year_geo_(year, st, "STATE",
                                      show_progress = show_progress) %>%
                # convert STATE fips to state abbreviation
                .[, state := convert_fips_to_names(STATE)] %>%
                setkey(LOGRECNO)
        }


        # read estimate and margin from each file
        if(!is.null(table_contents)){
            # get files for table contents, follow the notation of read_tablecontent.R
            dt <- read_acs5year_tablecontents_(year, st, table_contents,
                                               "e", show_progress)
            if (with_margin) {
                margin <- read_acs5year_tablecontents_(year, st, table_contents,
                                                       "m", show_progress)

                dt <- merge(dt, margin)
            }

            acs <- merge(geo, dt)
        } else {
            acs <- geo
        }

        # add coordinates
        acs <- add_coord(acs, st, geo_headers)


        # To determine what PLACE or COUSUB a tract or block group (partially)
        # blongs, replace PLACE and COUSUB with those obtained from census 2010
        # in generate_geoid_coordinate.R
        acs <- add_geoheader(acs, st, geo_headers, summary_level)

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
    begin <- c("area", "GEOID", "lon", "lat")
    end <- c("GEOCOMP", "SUMLEV", "NAME")
    setcolorder(selected, c(begin, setdiff(names(selected), c(begin, end)), end))

    return(selected)
}





read_acs5year_geoheaders_ <- function(year,
                                      states,
                                      table_contents = NULL,
                                      geo_headers = NULL,
                                      summary_level = "*",
                                      geo_comp = "*",
                                      with_margin = FALSE,
                                      with_acsgeoheaders = FALSE,
                                      show_progress = TRUE){
    # read ACS 5-year data of selected geoheaders
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
    # aaa = read_acs5year_geoheaders_(
    #     year = 2015,
    #     states = "ri",
    #     table_contents = "B01001_009",
    #     geo_headers = c("PLACE"),
    #     summary_level = "block group"
    # )
    #
    # No area names are given if there are multiple geoheaders.
    # bbb <- read_acs5year_geoheaders_(
    #     year = 2015,
    #     states = c("ut", "ri"),
    #     table_contents = c("B01001_009", "B00001_001"),
    #     geo_headers = c("COUNTY", "COUSUB", "PLACE"),
    #     summary_level = "block group"
    # )

    #=== prepare arguments ===

    states <- toupper(states)
    # toupper(NULL) ---> character(0) will cause trouble
    if (!is.null(table_contents)) table_contents <- toupper(table_contents)

    # switch summary level to code when it is given as plain text
    summary_level <- switch_summarylevel(summary_level)
    geo_comp <- switch_geocomp(geo_comp)


    # lookup of the year
    lookup <- get(paste0("lookup_acs5year_", year))

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
            geo <- read_acs5year_geo_(year, st, c(geo_headers, "STATE"),
                                      show_progress = show_progress) %>%
                # convert STATE fips to state abbreviation
                .[, state := convert_fips_to_names(STATE)] %>%
                setnames(geo_headers, paste0("acs_", geo_headers)) %>%
                setkey(LOGRECNO)
        }else {
            geo <- read_acs5year_geo_(year, st, "STATE",
                                      show_progress = show_progress) %>%
                # convert STATE fips to state abbreviation
                .[, state := convert_fips_to_names(STATE)] %>%
                .[, STATE := NULL] %>%
                setkey(LOGRECNO)
        }


        # read estimate and margin from each file
        if(!is.null(table_contents)){
            # get files for table contents, follow the notation of read_tablecontent.R
            dt <- read_acs5year_tablecontents_(year, st, table_contents,
                                               "e", show_progress)
            if (with_margin) {
                margin <- read_acs5year_tablecontents_(year, st, table_contents,
                                                       "m", show_progress)

                dt <- merge(dt, margin)
            }

            acs <- merge(geo, dt)
        } else {
            acs <- geo
        }

        # add coordinates and geoheaders from Census 2010 data
        acs <- add_coord(acs, st, geo_headers)

        # To determine what PLACE or COUSUB a tract or block group (partially)
        # blongs, replace PLACE and COUSUB with those obtained from census 2010
        # in generate_geoid_coordinate.R
        acs <- add_geoheader(acs, st, geo_headers, summary_level)

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
        begin <- c("area", "GEOID", "lon", "lat")
    } else {
        begin <- c("GEOID", "lon", "lat")
    }
    end <- c("GEOCOMP", "SUMLEV", "NAME")
    setcolorder(combined, c(begin, setdiff(names(combined), c(begin, end)), end))

    return(combined)
}






read_acs5year_geo_ <- function(year,
                               state,
                               geo_headers = NULL,
                               show_progress = TRUE) {
    # Read geography file of one state of ACS 5-year survey and return a
    # data.table of selected geographic headers plus LOGRECNO, SUMLEV, and
    # GEOCOMP

    # Args_____
    # year : integer, year of 5-year census
    # state : string, state abbreviation such as "MA"
    # geo_headers : string vector of geographic headers such as c("PLACE", "CBSA")
    # show_progress : wheather to show the progress of fread()
    #
    # Return_____
    # a data.table with key of LOGRECNO
    #
    # Examples_____
    # aaa = read_acs5year_geo_(2015, "ri", c(NAME, STATE))



    #=== prepare arguments ===

    path_to_census <- Sys.getenv("PATH_TO_CENSUS")

    # allow lowercase input for state and geo_headers
    state <- tolower(state)
    geo_headers <- toupper(geo_headers) %>%
        unique()

    if (show_progress) {
        cat("\nReading", toupper(state), year, "ACS 5-year survey geography file\n")
    }

    #=== read file ===
    if (year >= 2011){
        dict_geoheader <- dict_acs_geoheader
    } else if (year == 2010){
        dict_geoheader <- dict_acs_geoheader_2010
    }else if (year == 2009){
        dict_geoheader <- dict_acs_geoheader_2009_5year
    }


    file <- paste0(path_to_census, "/acs5year/", year, "/g", year, "5",
                   tolower(state), ".csv")

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




read_acs5year_1_file_tablecontents_ <- function(year, state, file_seg,
                                                table_contents, est_marg = "e",
                                                show_progress = TRUE){
    # read selected table contents from a single file segement
    #
    # Args_____
    # year : end year of the 5-year survey
    # state : abbreviation of a state, such as "IN"
    # file_seg : sequence of a file segment, such as "0034"
    # table_contents : vector of references of table contents in above file segment
    # est_marg : which data to read, "e" for estimate and "m" for margin of error
    # show_progress : whether to show progress of fread()
    #
    # Return_____
    # a data.table with key LOGRECNO
    #
    # Examples_____
    # aaa <- read_acs5year_1_file_tablecontents_(
    #     2015, "RI", "0122", c("B992708_002", "B992709_001", "B992709_003")
    # )


    path_to_census <- Sys.getenv("PATH_TO_CENSUS")

    # get column names from file segment, then add six ommitted ones
    lookup <- get(paste0("lookup_acs5year_", year))
    col_names <- lookup[file_segment == file_seg] %>%
        # get rid of references ending with ".5", which are not in the file
        .[str_extract(reference, "..$") != ".5", reference]
    ommitted <- c("FILEID", "FILETYPE", "STUSAB", "CHARITER", "SEQUENCE", "LOGRECNO")
    col_names <- c(ommitted, col_names)

    # row bind data in group1 and group2
    file1 <- paste0(path_to_census, "/acs5year/", year, "/", "group1/",
                    est_marg, year, "5", tolower(state), file_seg, "000.txt")
    file2 <- paste0(path_to_census, "/acs5year/", year, "/", "group2/",
                    est_marg, year, "5", tolower(state), file_seg, "000.txt")

    dt1 <- fread(file1, header = FALSE, showProgress = show_progress) %>%
        setnames(names(.), col_names) %>%
        .[, c("LOGRECNO", table_contents), with = FALSE]

    # convert non-numeric columns to numeric
    # some missing data are denoted as ".", which lead to the whole column read
    # as character
    for (col in names(dt1)){
        if (is.character(dt1[, get(col)])){
            dt1[, (col) := as.numeric(get(col))]
        }
    }


    if(toupper(state) == "US"){
        # US has empty files in group2 as it has no data at tract and block
        # group level, which causes fread error
        dt2 = NULL
    } else {
        dt2 <- fread(file2, header = FALSE, showProgress = show_progress) %>%
            setnames(names(.), col_names) %>%
            .[, c("LOGRECNO", table_contents), with = FALSE]
    }

    for (col in names(dt2)){
        if (is.character(dt2[, get(col)])){
            dt2[, (col) := as.numeric(get(col))]
        }
    }

    combined <- rbindlist(list(dt1, dt2)) %>%
        #.[, c("LOGRECNO", table_contents), with = FALSE] %>%
        # add "_e" or "_m" to show the data is estimate or margin
        setnames(table_contents, paste0(table_contents, "_", est_marg)) %>%
        setkey(LOGRECNO)

    # # convert non-numeric columns to numeric
    # # some missing data are denoted as ".", which lead to the whole column read
    # # as character
    # for (col in names(combined)){
    #     if (is.character(combined[, get(col)])){
    #         combined[, (col) := as.numeric(get(col))]
    #     }
    # }

    return(combined)
}




read_acs5year_tablecontents_ <- function(year, state, table_contents,
                                         est_marg = "e",
                                         show_progress = TRUE){
    # read table contents of a state
    #
    # Args_____
    # year : end year of the 5-year survey
    # state : state abbreviation such as "IN"
    # table_contents : vector of references of table contents
    # est_marg : data to read, "e" for estimate and "m" for margin of error
    # show_progress : whether to progress of f

    # Examples_____
    # aaa <- read_acs5year_tablecontents_(
    #     year = 2015,
    #     state = "ri",
    #     table_contents = c("B01001_009", "B00001_001", "B10001_002"),
    #     est_marg = "e"
    # )

    # locate data files for the content
    lookup <- get(paste0("lookup_acs5year_", year))
    file_content <- lookup_tablecontents(table_contents, lookup)

    dt <- purrr::map2(file_content[, file_seg],
                      file_content[, table_contents],
                      function(x, y) read_acs5year_1_file_tablecontents_(
                          year, state, file_seg = x, table_contents = y,
                          est_marg = est_marg,
                          show_progress = show_progress
                      )) %>%
        purrr::reduce(merge, all = TRUE)

    return(dt)
}

