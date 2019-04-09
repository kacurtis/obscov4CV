#' @importFrom magrittr %>%
#' @importFrom graphics abline axis legend lines mtext par plot points
#' @importFrom stats pnbinom ppois quantile var
#' @importFrom utils tail
#' @importFrom rlang .data
NULL 


## quiets concerns of R CMD check re: the .'s that appear in pipelines
## and the "n" that is produced by dplyr::count() in a pipeline
if (getRversion() >= "2.15.1") utils::globalVariables(c("n"))


# Hidden function to execute progress bar
progbar = function(it, total, shiny.progress=FALSE) {
  if (shiny.progress) {
    shiny::incProgress(500 / total)
  } else {
    svMisc::progress(it/total*100)
  }
}


#' Simulate CV response to observer coverage
#'
#' \code{sim_cv_obscov} simulates bycatch estimation CVs resulting from a range 
#' of observer coverage levels, given bycatch rate, negative binomial dispersion 
#' parameter, and total fishery effort. 
#' 
#' \code{sim_cv_obscov} runs \code{nsim} simulations per level of observer 
#' coverage, from the larger of 0.1\% or two sets/hauls to 100\%. Simulated 
#' bycatch estimates use a simple mean-per-unit approach with finite population 
#' correction. CV estimates exclude simulations with zero observed bycatch. 
#' Since estimating variance requires at least two numbers, total effort must 
#' be at least three sets/hauls to evaluate observer coverage less than 100\%. 
#' 
#' Warning: Large total effort (>100K sets/hauls) may require several minutes 
#' of execution time. Increasing \code{nsim} from the default of 1000 will 
#' also increase execution time. 
#' 
#' \strong{Caveat:} \code{sim_cv_obscov} assumes representative observer coverage 
#' and no hierarchical sources of variance (e.g., vessel- or trip-level variation). 
#' As a result, bycatch estimation CV for a given level of observer coverage is 
#' likely to be biased low relative to the real world. More conservative estimates 
#' can be obtained by using higher-level units of effort (e.g., 
#' \code{bpue} as mean bycatch per trip instead of bycatch per set/haul, and 
#' \code{te} as number of trips instead of number of sets/hauls).
#' 
#' @param te an integer greater than 2. Total effort in fishery (sets/hauls).
#' @param bpue a positive number. Bycatch per unit effort.
#' @param d a number greater than or equal to 1. Negative binomial dispersion 
#'   parameter. The dispersion parameter corresponds to the variance-to-mean 
#'   ratio of set-level bycatch, so \eqn{d = 1} corresponds to Poisson-distributed 
#'   bycatch, and \eqn{d > 1} corresponds to overdispersed bycatch.
#' @param nsim a positive integer. Number of simulations to run.
#' @param ...  additional arguments for compatibility with Shiny.
#'   
#' @return A list with components:
#'   \item{simdat}{a tibble with one row per simulation and the following fields: 
#'   simulated proportion observer coverage (\code{simpoc}), number of observed sets 
#'   (\code{nobsets}), total observed bycatch (\code{ob}), variance of observed 
#'   bycatch (\code{obvar}), mean observed bycatch per unit effort (\code{xsim}), 
#'   finite population correction (\code{fpc}), standard error of observed bycatch 
#'   per unit effort (\code{sesim}), and CV of observed bycatch per unit effort 
#'   (\code{cvsim}). 
#'   For simulations with zero observed bycatch, \code{cvsim} will be NaN.}
#'   \item{bpue}{the bycatch per unit effort used.}
#'   \item{d}{the negative binomial dispersion parameter used.}
#'   
#' @export 
sim_cv_obscov <- function(te, bpue, d=2, nsim=1000, ...) {  
  if (te<20) obscov <- 1:te/te 
  else obscov <- c(seq(0.001,0.005,0.001), seq(0.01,0.05,0.01), seq(0.10,1,0.05))
  simdat <- tibble::tibble(simpoc = rep(obscov, nsim), 
                           nobsets = round(.data$simpoc * te)) %>% 
    dplyr::filter(.data$nobsets > 1) %>% 
    dplyr::mutate(ob=NA, obvar=NA)
  set.seed(Sys.time())
  
  for (i in 1:nrow(simdat)) {
    obsets <- if(d==1) Runuran::urpois(simdat$nobsets[i], bpue) 
    else Runuran::urnbinom(simdat$nobsets[i], size=(bpue/(d-1)), prob=1/d)
    simdat$ob[i] <- sum(obsets)
    simdat$obvar[i] <- stats::var(obsets)

    if (i %% 500 == 0) progbar(i, nrow(simdat), ...)
  }
  
  simdat <- simdat %>% 
    dplyr::mutate(xsim=.data$ob/.data$nobsets, fpc=1-.data$nobsets/te, 
                  sesim=sqrt(.data$fpc*.data$obvar/.data$nobsets), 
                  cvsim=.data$sesim/.data$xsim)
  return(list(simdat=simdat, bpue=bpue, d=d))
}


#' Plot CV vs. observer coverage
#' 
#' \code{plot_cv_obscov} plots CV of bycatch estimates vs observer coverage for
#' user-specified percentile (i.e., probability of achieving CV) and several 
#' default percentiles, and returns minimum observer coverage needed to achieve 
#' user-specified target CV and percentile. 
#'   
#' @param simlist list output from \code{sim_cv_obscov}.
#' @param targetcv a non-negative number less than or equal to 100. Target CV 
#'   (as percentage). If \eqn{targetcv = 0}, no corresponding minimum observer 
#'   coverage will be highlighted.
#' @param q a positive number less than or equal to 0.95. Custom percentile to 
#'   be plotted, desired probability (as a proportion) of achieving the target 
#'   CV or lower. Ignored if \eqn{targetcv = 0}.
#' 
#' @details  
#' \strong{Caveat:} Since \code{sim_cv_obscov} assumes representative observer 
#' coverage and no hierarchical sources of variance (e.g., vessel- or trip-level 
#' variation), bycatch estimation CV for a given level of observer coverage is 
#' likely to be biased low relative to the real world. See documentation for
#' \code{sim_obs_cov} for additional details.
#'   
#' @return A list with components:
#'   \item{pobscov}{minimum observer coverage in terms of percentage.} 
#'   \item{nobsets}{corresponding observed effort.}
#' @return Returned invisibly. 
#'   
#' @export 
plot_cv_obscov <- function(simlist=simlist, targetcv=30, q=0.8) {
  # get quantiles of bycatch estimation CVs
  simsum <- simlist$simdat %>% 
    dplyr::filter(.data$ob>0) %>% 
    dplyr::group_by(.data$simpoc) %>% 
    dplyr::summarize(nsim=n(), meanob=mean(.data$ob), nobsets=mean(.data$nobsets), 
                     qcv=stats::quantile(.data$cvsim,q,na.rm=T), 
                     q50=stats::quantile(.data$cvsim,0.5,na.rm=T), 
                     q80=stats::quantile(.data$cvsim,0.8,na.rm=T), 
                     q95=stats::quantile(.data$cvsim,0.95,na.rm=T), 
                     min=min(.data$ob), max=max(.data$ob))
  # plot 
  with(simsum, plot(100*simpoc, 100*qcv, 
                    xlim=c(0,100), ylim=c(0,100), xaxs="i", yaxs="i", xaxp=c(0,100,10), yaxp=c(0,100,10),
                    xlab="Observer Coverage (%)", ylab="CV of Bycatch Estimate (%)",
                    main="CV of Bycatch Estimate vs Observer Coverage"))
  with(simsum, polygon(c(100*simsum$simpoc[1],100*simsum$simpoc,100,0), c(100,100*q50,100,100),col="gray90", lty=0))
  with(simsum, polygon(c(100*simsum$simpoc[1],100*simsum$simpoc,100,0), c(100,100*q80,100,100),col="gray80", lty=0))
  with(simsum, polygon(c(100*simsum$simpoc[1],100*simsum$simpoc,100,0), c(100,100*q95,100,100),col="gray70", lty=0))
  with(simsum, points(100*simpoc, 100*qcv))
  with(simsum, lines(100*simpoc, 100*qcv))
  abline(h=100, v=100)
  legpos <- ifelse(any(simsum$simpoc > 0.7 & simsum$q95 > 0.5), "bottomleft", "topright")
  # get (and add to plot) minimum required observer coverage
  if (targetcv) {
    abline(h=targetcv, col=2, lwd=2, lty=2)
    targetoc <- simsum %>% dplyr::filter(.data$qcv <= targetcv/100) %>% 
      dplyr::filter(.data$simpoc==min(.data$simpoc))
    par(xpd=TRUE)
    points(targetoc$simpoc*100, targetoc$qcv*100, pch=8, col=2, cex=1.5, lwd=2)
    par(xpd=FALSE)
    legend(legpos, lty=c(2,0,1,0,0,0), pch=c(NA,8,1,rep(15,3)), col=c(2,2,1,"gray90","gray80","gray70"), 
           lwd=c(2,2,rep(1,4)), pt.cex=1.5, y.intersp=1.1,
           legend=c("target CV", "min coverage", paste(q*100,"th percentile", sep=""),
                    ">50th percentile",">80th percentile",">95th percentile"))
  } else {
    legend(legpos, lty=c(1,0,0,0), pch=c(1,rep(15,3)), col=c(1,"gray90","gray80","gray70"), 
           lwd=c(rep(1,4)), pt.cex=1.5, y.intersp=1.1,
           legend=c(paste(q*100,"th percentile", sep=""), 
                    ">50th percentile",">80th percentile",">95th percentile"))
  }
  # return recommended minimum observer coverage
  if (targetcv)
    cat(paste("Minimum observer coverage to achieve ", targetcv, "% CV or less with ", q*100, "% probability is ", 
            round(targetoc$simpoc*100), "% (", targetoc$nobsets, " hauls).\n", 
            "Please review the caveats in the associated documentation.\n", sep=""))
  cat("Note that results are simulation-based and may vary slightly with repetition.\n")
  if (targetcv) 
    return(invisible(list(pobscov = targetoc$simpoc*100, nobsets=targetoc$nobsets)))
}


#' Get probability of zero bycatch given effort, bycatch rate, and dispersion
#' 
#' \code{get_probzero} returns probability of zero bycatch in a specified number 
#' of sets/hauls, given bycatch per unit effort and negative binomial dispersion 
#' parameter. 
#' 
#' @param n a vector of positive integers. Observed effort levels (in terms of 
#'   sets/hauls) for which to calculate probability of zero bycatch.
#' @param bpue a positive number. Bycatch per unit effort.
#' @param d a number greater than or equal to 1. Negative binomial dispersion 
#'   parameter. The dispersion parameter corresponds to the variance-to-mean 
#'   ratio of set-level bycatch, so \eqn{d = 1} corresponds to Poisson-distributed 
#'   bycatch, and \eqn{d > 1} corresponds to overdispersed bycatch.
#'   
#' @details
#' Calculated from the probability density at zero of the corresponding Poisson
#' (\eqn{d = 1}) or negative binomial (\eqn{d < 1}) distribution.
#' 
#' \strong{Caveat:} \code{get_probzero} assumes representative observer coverage 
#' and no hierarchical sources of variance (e.g., vessel- or trip-level variation), 
#' so probability of observing zero bycatch at a given level of observer coverage 
#' is likely to be biased low relative to the real world. More conservative 
#' estimates can be obtained by using higher-level units of effort 
#' (e.g., \code{bpue} as mean bycatch per trip instead of bycatch per set/haul, and 
#' \code{n} as number of trips instead of number of sets/hauls).
#'   
#' @return Vector of same length as \code{n} with probabilities of zero bycatch. 
#' @return Returned invisibly
#' 
#' @export
get_probzero <- function(n, bpue, d) {
  pz <- if(d==1) stats::ppois(0, bpue)^n 
  else stats::pnbinom(0, size=(bpue/(d-1)), prob=1/d)^n
  return(invisible(pz))
}


#' Plot sample size for CV estimates vs observer coverage
#' 
#' \code{plot_cvsim_samplesize} plots sample size (simulations with positive
#' observed bycatch) vs observer coverage level, along with probability of 
#' observing zero bycatch based on effort and the probability density at zero
#' given bycatch rate and negative binomial dispersion. 
#' 
#' Note that the predicted probability of observing zero bycatch assumes 
#' representative observer coverage and no hierarchical sources of variance 
#' (e.g., vessel- or trip-level variation), so probability of observing zero 
#' bycatch at a given level of observer coverage is likely to be biased low 
#' relative to the real world. 
#' 
#' @param simlist List output from sim_cv_obscov.
#' 
#' @return None
#' 
#' @export 
plot_cvsim_samplesize <- function(simlist=simlist) {
  s <- simlist$simdat %>% 
    dplyr::filter(.data$ob>0) %>% 
    dplyr::group_by(.data$simpoc, .data$nobsets) %>% 
    dplyr::summarize(npos=n())
  pz <- get_probzero(s$nobsets, simlist$bpue, simlist$d)
  omar <- graphics::par()$mar
  graphics::par(mar = c(4.1,4.1,3,4.1))
  with(s, plot(100*simpoc, npos, pch=22,
               xlim=c(0,100), ylim=c(0,round(max(npos),-1)+10), xaxs="i", yaxs="i",
               xaxp=c(0,100,10), yaxp=c(0,1000,10),
               xlab="Observer Coverage (%)", ylab="Simulations with Positive Bycatch",
               main="Sample Size for CV Estimates"))
  graphics::par(new=T)
  plot(100*s$simpoc, 100*pz, type="l", lwd=2, xaxs="i", yaxs="i", xlim=c(0,100), ylim=c(0,100),
       axes=F, xlab=NA, ylab=NA, col=2)
  axis(side = 4, col=2, col.axis=2)
  mtext(side = 4, line = 3, "Probability of Zero Bycatch (%)", col=2)
  abline(h=100*tail(pz,1), lty=3, lwd=2, col=2)
  legpos <- ifelse(any(s$simpoc > 0.7 & pz < 0.2), "right", "bottomright")
  legend(legpos, lty=c(1,3), col=2, lwd=2, text.col=2, bty="n", legend=c("in observed effort","in total effort"))
  graphics::par(mar=omar)
}  


#' Plot probability of positive observed bycatch vs observer coverage
#' 
#' \code{plot_probposobs} plots probability of observing at least one bycatch 
#'   event vs observer coverage, given total effort in sets/hauls, bycatch per 
#'   unit effort, and negative binomial dispersion parameter. 
#'   
#' @param te an integer greater than 1. Total effort in fishery (sets/hauls).
#' @param bpue a positive number. Bycatch per unit effort.
#' @param d a number greater than or equal to 1. Negative binomial dispersion 
#'   parameter. The dispersion parameter corresponds to the variance-to-mean 
#'   ratio of set-level bycatch, so \eqn{d = 1} corresponds to Poisson-distributed 
#'   bycatch, and \eqn{d > 1} corresponds to overdispersed bycatch.
#' @param target.ppos a non-negative number less than or equal to 100. Target 
#'   probability of positive observed bycatch (as percentage), given positive 
#'   bycatch in total effort. If 0, no corresponding minimum observer coverage 
#'   will be highlighted.
#' 
#' @details  
#' Probabilities are based on the probability density function for the 
#' corresponding Poisson or negative binomial distribution.
#' 
#' The probability that any bycatch occurs in the given total effort is shown
#' by the horizontal black dotted line. The conditional probability of observing 
#' any bycatch if it occurs is shown by the solid black line.  The product of 
#' these first two probabilities gives the absolute probability of observing any
#' bycatch (dashed black line).The minimum observer coverage to achieve the target 
#' obability of observing bycatch if it occurs (x-axis value of red star) is 
#' where the conditional bycatch detection probability (solid black line) 
#' intersects with the target probability (red dash-dot line).
#' 
#' Note that unlike \code{plot_cv_obscov}, \code{plot_probposobs} is designed 
#' as a one-step tool, and does not take output from user calls to 
#' \code{get_probzero}. 
#'   
#' \strong{Caveat:} \code{plot_probposobs} assumes representative observer coverage 
#' and no hierarchical sources of variance (e.g., vessel- or trip-level variation), 
#' so probability of observing bycatch at a given level of observer coverage 
#' is likely to be biased high relative to the real world. More conservative 
#' estimates can be obtained by using higher-level units of effort 
#' (e.g., \code{bpue} as mean bycatch per trip instead of bycatch per set/haul, and 
#' \code{te} as number of trips instead of number of sets/hauls).
#' 
#' @return A list with components:
#'   \item{pobscov}{minimum observer coverage in terms of percentage.} 
#'   \item{nobsets}{corresponding observed effort.}
#' @return Returned invisibly. 
#' 
#' @export 
plot_probposobs <- function(te, bpue, d, target.ppos=80) {
  # percent probablity of positive observed bycatch
  if (te<1000) obscov <- 1:te/te 
  else obscov <- seq(0.001,1,0.001)
  oc <- tibble::tibble(obscov = obscov,
               nobsets = round(.data$obscov * te)) %>% 
    dplyr::filter(.data$nobsets>0) %>% as.data.frame()
  oc$pp <- 1-get_probzero(oc$nobsets, bpue, d)   # probability of positive observed bycatch
  ppt <- tail(oc$pp,1)   # probability of positive bycatch in total effort
  plot(100*oc$obscov, 100*(oc$pp/ppt), type="l", lty=1, lwd=2,
       xlim=c(0,100), ylim=c(0,100), xaxs="i", yaxs="i", xaxp=c(0,100,10), yaxp=c(0,100,10),
       xlab="Observer Coverage (%)", ylab="Probability of Positive Bycatch (%)",
       main="Probability of Positive Bycatch")
  abline(h=100*ppt,lwd=2, lty=3)
  lines(100*oc$obscov, 100*oc$pp, lwd=2, lty=2)
  lines(100*oc$obscov, 100*(oc$pp/ppt), lwd=2)
  legpos <- ifelse(any(oc$obscov > 0.6 & oc$pp < 0.3 ), "topleft", "bottomright")
  if (target.ppos) {
    abline(h=target.ppos, col=2, lwd=2, lty=4)
    targetoc <- log(1-(target.ppos/100)*ppt)/log(get_probzero(1,bpue,d))/te #which.max(100*oc$pp/ppt >= target.ppos)
    par(xpd=TRUE)
    points(targetoc*100, target.ppos, pch=8, col=2, cex=1.5, lwd=2)
    par(xpd=FALSE)
    legend(legpos, lty=c(1,2,3,4,NA), pch=c(NA,NA,NA,NA,8), lwd=2, col=c(1,1,1,2,2), pt.cex=1.5, 
           legend=c("in observed effort if total bycatch > 0", "in observed effort",
                    "in total effort", "in target observer coverage", "min coverage"))
  } else {
    legend(legpos, lty=c(1,2,3), lwd=2, col=1, 
           legend=c("in observed effort if total bycatch > 0","in observed effort","in total effort"))
  }
  # return recommended minimum observer coverage
  if (target.ppos) {
    cat(paste("Minimum observer coverage to achieve at least ", target.ppos, 
              "% probability of observing \nbycatch when total bycatch is positive is ", 
              signif(targetoc*100,3), "% (", ceiling(targetoc*te), " sets).\n",
              "Please review the caveats in the associated documentation.\n", sep=""))
    return(invisible(list(pobscov=round(targetoc*100,1), nobsets=ceiling(targetoc*te))))
  }
}