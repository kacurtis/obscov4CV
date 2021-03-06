#' Simulate CV response to observer coverage
#'
#' \code{sim_cv_obscov} simulates bycatch estimation CVs for a range 
#' of observer coverage levels, given bycatch rate, dispersion 
#' index, and total fishery effort. The resulting object is required by 
#' \code{plot_cv_obscov} for visualization.  
#' 
#' \code{sim_cv_obscov} runs \code{nsim} simulations per level of observer 
#' coverage, from the larger of 0.1\% or one trip/set to 100\%. Simulated 
#' bycatch estimates are calculated as mean observed bycatch per unit effort. 
#' CV at each observer coverage level is calculated as the square root of mean 
#' square estimation error divided by "true" bycatch (\code{bpue}).
#' 
#' Warning: Large total effort (>100K trips/sets) may require several minutes 
#' of execution time. Increasing \code{nsim} from the default of 1000 will 
#' also increase execution time. 
#' 
#' \strong{Caveat:} \code{sim_cv_obscov} assumes representative observer coverage 
#' and no hierarchical sources of variance (e.g., vessel- or trip-level variation). 
#' Violating these assumptions will likely result in negatively biased projections of 
#' bycatch estimation CV for a given level of observer coverage. More conservative 
#' projections can be obtained by using higher-level units of effort (e.g., 
#' \code{bpue} as mean bycatch per trip instead of bycatch per trip/set, and 
#' \code{te} as number of trips instead of number of trips/sets).
#' 
#' @param te an integer greater than one. Total effort in fishery (trips/sets).
#' @param bpue a positive number. Bycatch per unit effort.
#' @param d a number greater than or equal to 1. Dispersion 
#'   index. The dispersion index corresponds to the variance-to-mean 
#'   ratio of effort-unit-level bycatch, so \eqn{d = 1} corresponds to Poisson-
#'   distributed bycatch, and \eqn{d > 1} corresponds to overdispersed bycatch.
#' @param nsim a positive integer. Number of simulations to run.
#' @param ...  additional arguments for compatibility with Shiny.
#'   
#' @return A list with components:
#'   \item{simsum}{a tibble with one row per observer coverage level and the 
#'   following fields: simulated proportion observer coverage (\code{pobs}), 
#'   number of observed trips/sets (\code{nobs}), and bycatch estimation CV 
#'   (\code{cvsim}).} 
#'   \item{simdat}{a tibble with one row per simulation and the following fields: 
#'   simulated proportion observer coverage (\code{pobs}), number of observed 
#'   trips/sets (\code{nobs}), true (realized) bycatch per unit effort (\code{tbpue}), 
#'   observed bycatch per unit effort (\code{obpue}), and error of observed bycatch 
#'   per unit effort (\code{oberr} = \code{obpue} - \code{tbpue}).}
#'   \item{bpue}{the nominal bycatch per unit effort used in the simulations.}
#'   \item{d}{the dispersion index used in the simulations.}
#'   
#' @export 
sim_cv_obscov <- function(te, bpue, d = 2, nsim = 1000, ...) {
  
  # check input values
  if ((ceiling(te) != floor(te)) || te<2) stop("te must be a positive integer > 1")
  if (bpue<=0) stop("bpue must be > 0")
  if (d<1) stop("d must be >= 1")
  if ((ceiling(nsim) != floor(nsim)) || nsim<=0) stop("nsim must be a positive integer")
  
  # simulate observer coverage and bycatch estimation
  if (te<20) { oc <- 1:te/te 
  } else { oc <- c(seq(0.001,0.005,0.001), seq(0.01,0.05,0.01), seq(0.10,1,0.05)) }
  simdat <- tibble::tibble(pobs = rep(oc, nsim), 
                           nobs = round(.data$pobs * te)) %>% 
    dplyr::filter(.data$nobs > 0) %>% 
    dplyr::mutate(tbpue=NA, obpue=NA, oberr=NA)
  set.seed(Sys.time())
  pb <- progress_init(...)
  
  for (i in 1:nrow(simdat)) {
    ue <- if(d==1) { Runuran::urpois(te, bpue) 
    } else { Runuran::urnbinom(te, size=(bpue/(d-1)), prob=1/d) }
    obs <- sample(ue, simdat$nobs[i])
    simdat$tbpue[i] <- mean(ue)
    simdat$obpue[i] <- mean(obs)
    simdat$oberr[i] <- simdat$obpue[i] - simdat$tbpue[i]
    
    if (i %% 500 == 0) {
      pb <- progbar(i, nrow(simdat), pb, ...)
    }
  }
  
  simsum <- simdat %>% dplyr::group_by(.data$pobs) %>% 
    dplyr::summarize(nobs=unique(.data$nobs),
                     cvsim=sqrt(mean(.data$oberr^2))/bpue)
  return(list(simsum=simsum, simdat=simdat, te=te, bpue=bpue, d=d))
}
