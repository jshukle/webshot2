#' @import chromote
#' @import later
#' @import promises
#'
NULL


#' Take a screenshot of a URL
#'
#' @param url A vector of URLs to visit. If multiple URLs are provided, it will
#'   load and take screenshots of those web pages in parallel.
#' @param file A vector of names of output files. Should end with an image file
#'   type (`.png`, `.jpg`, `.jpeg`, or `.webp`) or
#'   `.pdf`. If several screenshots have to be taken and only one filename
#'   is provided, then the function appends the index number of the screenshot
#'   to the file name. For PDF output, it is just like printing the page to PDF
#'   in a browser; `selector`, `cliprect`, `expand`, and
#'   `zoom` will not be used for PDFs.
#' @param vwidth,vheight Viewport width and height. This is the width or height
#'   of the virtual browser "window". Chrome expects integer values; numeric
#'   values are rounded to the nearest integer.
#' @param selector One or more CSS selectors specifying a DOM element to set the
#'   clipping rectangle to. The screenshot will contain these DOM elements. For
#'   a given selector, if it has more than one match, all matching elements will
#'   be used. This option is not compatible with `cliprect`.
#'
#'   When taking screenshots of multiple URLs, this parameter can also be a list
#'   with same length as `url` with each element of the list containing a
#'   vector of CSS selectors to use for the corresponding URL.
#' @param cliprect Clipping rectangle. If `cliprect` and `selector`
#'   are both unspecified, the clipping rectangle will contain the entire page.
#'   This can be the string `"viewport"`, in which case the clipping
#'   rectangle matches the viewport size, or it can be a four-element numeric
#'   vector specifying the left, top, width, and height. (Note that the order of
#'   left and top is reversed from the original webshot package.) This option is
#'   not compatible with `selector`.
#'
#'   When taking screenshots of multiple URLs, this parameter can also be a list
#'   with same length as `url` with each element of the list being
#'   "viewport" or a four-elements numeric vector.
#' @param delay Time to wait before taking screenshot, in seconds. Sometimes a
#'   longer delay is needed for all assets to display properly.
#' @param expand A numeric vector specifying how many pixels to expand beyond
#'   the clipping rectangle determined by `selector`. If one number, the
#'   rectangle will be expanded by that many pixels on all sides. If four
#'   numbers, they specify the top, right, bottom, and left, in that order.
#'   This argument is only applied when `selector` is used and is not compatible
#'   with `cliprect`.
#'
#'   When taking screenshots of multiple URLs, this parameter can also be a list
#'   with same length as `url` with each element of the list containing a
#'   single number or four numbers to use for the corresponding URL.
#' @param zoom A number specifying the zoom factor. A zoom factor of 2 will
#'   result in twice as many pixels vertically and horizontally. Note that using
#'   2 is not exactly the same as taking a screenshot on a HiDPI (Retina)
#'   device: it is like increasing the zoom to 200% in a desktop browser and
#'   doubling the height and width of the browser window. This differs from
#'   using a HiDPI device because some web pages load different,
#'   higher-resolution images when they know they will be displayed on a HiDPI
#'   device (but using zoom will not report that there is a HiDPI device).
#' @param useragent The User-Agent header used to request the URL.
#' @param max_concurrent (Currently not implemented)
#' @param quiet If `TRUE`, status updates via console messages are suppressed.
#' @template webshot-return
#'
#' @examples
#' if (interactive()) {
#'
#' # Whole web page
#' webshot("https://github.com/rstudio/shiny")
#'
#' # Might need a delay for all assets to display
#' webshot("http://rstudio.github.io/leaflet", delay = 0.5)
#'
#' # One can also take screenshots of several URLs with only one command.
#' # This is more efficient than calling 'webshot' multiple times.
#' webshot(c("https://github.com/rstudio/shiny",
#'           "http://rstudio.github.io/leaflet"),
#'         delay = 0.5)
#'
#' # Clip to the viewport
#' webshot("http://rstudio.github.io/leaflet", "leaflet-viewport.png",
#'         cliprect = "viewport")
#'
#' # Specific size
#' webshot("https://www.r-project.org", vwidth = 1600, vheight = 900,
#'         cliprect = "viewport")
#'
#' # Manual clipping rectangle
#' webshot("http://rstudio.github.io/leaflet", "leaflet-clip.png",
#'         cliprect = c(200, 5, 400, 300))
#'
#' # Using CSS selectors to pick out regions
#' webshot("http://rstudio.github.io/leaflet", "leaflet-menu.png", selector = ".list-group")
#' # With multiple selectors, the screenshot will contain all selected elements
#' webshot("http://reddit.com/", "reddit-top.png",
#'         selector = c("[aria-label='Home']", "input[type='search']"))
#'
#' # Expand selection region
#' webshot("http://rstudio.github.io/leaflet", "leaflet-boxes.png",
#'         selector = "#installation", expand = c(10, 50, 0, 50))
#'
#' # If multiple matches for a given selector, it will take a screenshot that
#' # contains all matching elements.
#' webshot("http://rstudio.github.io/leaflet", "leaflet-p.png", selector = "p")
#' webshot("https://github.com/rstudio/shiny/", "shiny-stats.png",
#'          selector = "ul.numbers-summary")
#'
#' # Result can be piped to other commands like resize() and shrink()
#' webshot("https://www.r-project.org/", "r-small.png") %>%
#'  resize("75%") %>%
#'  shrink()
#'
#' }
#'
#' @export
webshot <- function(
  url = NULL,
  file = "webshot.png",
  vwidth = 992,
  vheight = 744,
  selector = NULL,
  cliprect = NULL,
  expand = NULL,
  delay = 0.2,
  zoom = 1,
  useragent = NULL,
  max_concurrent = getOption("webshot.concurrent", default = 6),
  quiet = getOption("webshot.quiet", default = FALSE)
) {
  if (length(url) == 0) {
    stop("Need url.")
  }

  # Ensure urls are either web URLs or local file URLs.
  url <- vapply(
    url,
    function(x) {
      if (!is_url(x)) {
        # `url` is a filename, not an actual URL. Convert to file:// format.
        file_url(x)
      } else {
        x
      }
    },
    character(1)
  )

  # Convert params cliprect, selector and expand to list if necessary, because
  # they can be vectors.
  if (!is.null(cliprect) && !is.list(cliprect)) cliprect <- list(cliprect)
  if (!is.null(selector) && !is.list(selector)) selector <- list(selector)
  if (!is.null(expand) && !is.list(expand)) expand <- list(expand)

  if (is.null(selector)) {
    selector <- "html"
  }

  # If user provides only one file name but wants several screenshots, then the
  # below code generates as many file names as URLs following the pattern
  # "filename001.png", "filename002.png", ... (or whatever extension it is)
  if (length(url) > 1 && length(file) == 1) {
    file <- vapply(1:length(url), FUN.VALUE = character(1), function(i) {
      replacement <- sprintf("%03d.\\1", i)
      gsub("\\.(.{3,4})$", replacement, file)
    })
  }

  # Check length of arguments and replicate if necessary
  args_all <- list(
    url = url,
    file = file,
    vwidth = as_pixels_int(vwidth), # Chrome requires integer viewport pxs
    vheight = as_pixels_int(vheight),
    selector = selector,
    cliprect = cliprect,
    expand = expand,
    delay = delay,
    zoom = zoom,
    useragent = useragent
  )

  n_urls <- length(url)
  args_all <- mapply(
    args_all,
    names(args_all),
    FUN = function(arg, name) {
      if (length(arg) == 0) {
        return(vector(mode = "list", n_urls))
      } else if (length(arg) == 1) {
        return(rep(arg, n_urls))
      } else if (length(arg) == n_urls) {
        return(arg)
      } else {
        stop(
          "Argument `",
          name,
          "` should be NULL, length 1, or same length as `url`."
        )
      }
    },
    SIMPLIFY = FALSE
  )

  args_all <- long_to_wide(args_all)

  cm <- default_chromote_object()

  # A list of promises for the screenshots
  res <- lapply(args_all, function(args) {
    new_session_screenshot(
      cm,
      args$url,
      args$file,
      args$vwidth,
      args$vheight,
      args$selector,
      args$cliprect,
      args$expand,
      args$delay,
      args$zoom,
      args$useragent,
      quiet
    )
  })

  p <- promise_all(.list = res)
  res <- cm$wait_for(p)
  res <- structure(unlist(res), class = "webshot")
  res
}


new_session_screenshot <- function(
  chromote,
  url,
  file,
  vwidth,
  vheight,
  selector,
  cliprect,
  expand,
  delay,
  zoom,
  useragent,
  quiet
) {
  filetype <- tolower(tools::file_ext(file))
  filetypes <- c(webshot_image_types(), "pdf")
  if (!filetype %in% filetypes) {
    stop("File extension must be one of: ", paste(filetypes, collapse = ", "))
  }

  if (is.null(selector)) {
    selector <- "html"
  }

  if (is.character(cliprect)) {
    if (cliprect == "viewport") {
      cliprect <- c(0, 0, vwidth, vheight)
    } else {
      stop("Invalid value for cliprect: ", cliprect)
    }
  } else {
    if (
      !is.null(cliprect) && !(is.numeric(cliprect) && length(cliprect) == 4)
    ) {
      stop(
        "`cliprect` must be a vector with four numbers, or a list of such vectors"
      )
    }
  }

  s <- NULL
  err <- NULL

  p <- chromote$new_session(
    wait_ = FALSE,
    width = vwidth,
    height = vheight
  )$then(function(session) {
    s <<- session

    if (!is.null(useragent)) {
      s$Network$setUserAgentOverride(userAgent = useragent)
    }
    res <- s$Page$loadEventFired(wait_ = FALSE)
    s$Page$navigate(url, wait_ = FALSE)
    res
  })$then(function(value) {
    # With chrome's new headless mode (v132+), the new session is initialized,
    # but our requested viewport size is ignored, so we set it explicitly.
    promise(function(resolve, reject) {
      s$Emulation$setDeviceMetricsOverride(
        width = vwidth,
        height = vheight,
        deviceScaleFactor = 1,
        mobile = FALSE,
        wait_ = FALSE
      )$then(function(result) {
        resolve(result)
      })
    })$catch(function(error) {
      warning(
        "Could not set viewport size to ",
        vwidth,
        "x",
        vheight,
        ": ",
        conditionMessage(error)
      )
      value
    })
  })$then(function(value) {
    if (delay > 0) {
      promise(function(resolve, reject) {
        later(
          function() {
            resolve(value)
          },
          delay
        )
      })
    } else {
      value
    }
  })$then(function(value) {
    if (filetype %in% webshot_image_types()) {
      s$screenshot(
        filename = file,
        selector = selector,
        cliprect = cliprect,
        expand = expand,
        scale = zoom,
        show = FALSE,
        wait_ = FALSE
      )
    } else if (filetype == "pdf") {
      # s$screenshot_pdf(
      #   filename = file,
      #   wait_ = FALSE,
      #   preferCSSPageSize = TRUE
      #   )
      res <- s$Page$printToPDF(
        printBackground = TRUE,
        preferCSSPageSize = TRUE,
        wait_ = TRUE
      )
      writeBin(base64enc::base64decode(res$data), file)
      file
    }
  })$then(function(value) {
    if (!isTRUE(quiet)) message(url, " screenshot completed")
    normalizePath(value)
  })$catch(function(err) {
    err <<- err
  })$finally(function() {
    # Close down the session if we successfully started one
    if (!is.null(s)) s$close()
    # Or rethrow the error if we caught one
    if (!is.null(err)) signalCondition(err)
  })

  p
}

webshot_image_types <- function() {
  c("png", "jpg", "jpeg", "webp")
}

knit_print.webshot <- function(x, ...) {
  lapply(x, function(filename) {
    res <- readBin(filename, "raw", file.size(filename))
    ext <- gsub(".*[.]", "", basename(filename))
    structure(list(image = res, extension = ext), class = "html_screenshot")
  })
}


#' @export
print.webshot <- function(x, ...) {
  invisible(x)
}
