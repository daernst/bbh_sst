# #' Reads BBH SST data
# #'
# #' @export
# #' @param filename string, the name of the file to read
# #' @return data.frame as a tibble
# 
# read_bbh <- function(filename = system.file("extdata/MaineDMR_Boothbay_Harbor_Sea_Surface_Temperatures.csv.gz", package = "bbh")){
#   if(!file.exists(filename[1])){
#     stop("File not found ", filename[1])
#   }
#   x <- readr::read_csv(filename[1],
#                        col_types = list(
#                          COLLECTION_DATE = readr::col_datetime(format = "%Y/%m/%d %H:%M:%S%z"),
#                          SEA_SURFACE_TEMP_MAX_C = readr::col_double(),
#                          SEA_SURFACE_TEMP_MIN_C = readr::col_double(),
#                          SEA_SURFACE_TEMP_AVG_C = readr::col_double(),
#                          ObjectId = readr::col_double()
#                        )) |>
#     dplyr::arrange(.data$COLLECTION_DATE)
#   class(x) <- c("sst", class(x))
#   return(x)
# }


#' Retrieve BBH data from the online portal
#' 
#' @seealso \href{https://dmr-maine.opendata.arcgis.com/datasets/5fd6f3e57d794a409d72f47d78f15a32_0/explore?showTable=true}{DMR Data Portal}
#' @export
#' @param uri character, the URI of the dataset 
#' @param form character, one of 'raw' to retrieve a list will all components or
#'   'data' to retrieve just the data of interest
#' @return a list or a tibble depending upon the value of \code{form}
fetch_bbh <- function(uri = "https://opendata.arcgis.com/datasets/5fd6f3e57d794a409d72f47d78f15a32_0.geojson",
                      form = c("raw", "data")[2]){
  
  x <- jsonlite::fromJSON(uri)
  
  if (tolower(form[1]) == 'data'){
    x <- x$features$properties |>
      dplyr::as_tibble() |>
      dplyr::mutate(COLLECTION_DATE = as.POSIXct(.data$COLLECTION_DATE, format = "%Y-%m-%dT%H:%M:%SZ", tz = "US/Eastern"),
                    COLLECTION_DATE = as.Date(.data$COLLECTION_DATE)) |>
      dplyr::select(-dplyr::any_of("ObjectId"))
    attr(x, "name") <- "BBH"
    attr(x, "source") <- uri
    attr(x, "longname") <- "Boothbay Harbor Maine"
    class(x) <- c("sst", class(x))
  }
  
  x
}


#' Make the URI needed for the specifed date range
#'
#' @export
#' @param begin character, the starting date as YYYY-mm-dd
#' @param end character, the end date as YYYY-mm-dd
#' @return character URI
make_uri <- function(begin = "2001-07-09", end = "2022-03-30"){
  pattern <- "http://www.neracoos.org/erddap/tabledap/E01_sbe37_all.csv?station%2Ctime%2Cmooring_site_desc%2Cconductivity%2Cconductivity_qc%2Ctemperature%2Ctemperature_qc%2Csalinity%2Csalinity_qc%2Csigma_t%2Csigma_t_qc%2Clongitude%2Clatitude%2Cdepth&time%3E=[BEGIN]T00%3A00%3A00Z&time%3C=[END]T23%3A00%3A00Z"
  x <- sub("[BEGIN]", begin, pattern, fixed = TRUE)
  sub("[END]", end, x, fixed = TRUE)
}


#' Fetch a table of buoy data between specified dates
#'
#' @export
#' @param begin character, the starting date as YYYY-mm-dd
#' @param end character, the end date as YYYY-mm-dd
#' @param form character, daily or hourly data
#' @return tibble of data
fetch_E01 <- function(begin = "2001-07-09", end = format(Sys.Date(),"%Y-%m-%d"), form = c("hourly", "daily")[1]){
  
  column_types <- list(
    station = readr::col_character(),
    time = readr::col_datetime("%Y-%m-%dT%H:%M:%SZ"),
    mooring_site_desc = readr::col_character(),
    conductivity = readr::col_double(),
    conductivity_qc = readr::col_double(),
    temperature = readr::col_double(),
    temperature_qc = readr::col_double(),
    salinity = readr::col_double(),
    salinity_qc = readr::col_double(),
    sigma_t = readr::col_double(),
    sigma_t_qc = readr::col_double(),
    longitude = readr::col_double(),
    latitude = readr::col_double(),
    depth = readr::col_double()
  )
  
  
  uri <- make_uri(begin = begin, end = end)
  
  resp <- httr::GET(uri) 
  
  x <- suppressWarnings(httr::content(resp, as = "parsed", col_types = column_types)) |>
    dplyr::slice(-1) 
  
  if(tolower(form)[1] == "daily"){
    x <- E01_bydate(x)
  }
  
  return(x)
}


#' Create by-date E01 data
#'
#'@export
#'@param x character, the E01 dataset
#'@return tibble
#'
E01_bydate <- function(x = fetch_E01()){
  x <- x |>
    dplyr::mutate(COLLECTION_DATE = as.Date(.data$time)) |> 
    dplyr::group_by(.data$COLLECTION_DATE) |>
    dplyr::summarise(SEA_SURFACE_TEMP_AVG_C = mean(.data$temperature, na.rm = TRUE),
                     SEA_SURFACE_TEMP_MIN_C = min(.data$temperature, na.rm = TRUE),
                     SEA_SURFACE_TEMP_MAX_C = max(.data$temperature, na.rm = TRUE))
  attr(x, "name") <- "E01"
  attr(x, "source") <- "http://www.neracoos.org/erddap/tabledap/E01_sbe37_all.html"
  attr(x, "longname") <- "Central Maine Shelf"
  class(x) <- c("sst", class(x))
  return(x)
}


#' Accepts name (BBH or EO1) and reads data
#' 
#' @export
#' @param name character, the name of the dataset
#' @return tibble
#' @param form character, daily or hourly data
#' 
fetch_sst <- function(name = "bbh", form = "daily"){
  x = switch(tolower(name)[1], 
             "bbh" = fetch_bbh(),
             "e01" = fetch_E01(form = form),
             stop("Name not known: ", name[1]))
  return(x)
}


#' Sets path name
#' 
#' @export
#' @param ... any filepath segments, optional
#' @param root root filepath, defaults to user directory
#' @return
#' 

get_path <- function(..., root = "C:\\Users\\ernst\\AppData\\Local/bbh/bbh"){
  ## make root if it doesn't exist
  if(!dir.exists(root)[1]){
    dir.create(root[1], recursive = TRUE)
  }
  file.path(root, ...)
}


