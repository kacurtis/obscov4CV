% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/target_obscov.r
\name{plot_uclnegobs}
\alias{plot_uclnegobs}
\title{Plot upper confidence limit of total bycatch for none observed}
\usage{
plot_uclnegobs(
  te,
  d = 3,
  cl = 95,
  target.ucl = 0,
  showplot = TRUE,
  silent = FALSE
)
}
\arguments{
\item{te}{an integer greater than 1. Total effort in fishery (sets/hauls).}

\item{d}{a number greater than or equal to 1. Negative binomial dispersion 
index. The dispersion index corresponds to the variance-to-mean 
ratio of set-level bycatch, so \eqn{d = 1} corresponds to Poisson-distributed 
bycatch, and \eqn{d > 1} corresponds to overdispersed bycatch.}

\item{cl}{a non-negative number less than or equal to 100. Confidence level
for upper confidence limit of bycatch (as percentage), given no bycatch 
observed.}

\item{target.ucl}{a non-negative number. Maximum allowable upper confidence 
limit for bycatch given zero bycatch observed. If 0, no corresponding 
minimum observer coverage will be highlighted.}

\item{showplot}{logical. If plot = FALSE, plotting is suppressed.}

\item{silent}{logical. If silent = TRUE, print output to terminal is suppressed.}
}
\value{
A list with components:
  \item{ucldat}{a tibble with the following fields: 
  proportion observer coverage (\code{pobs}), number of observed trips/sets
  (\code{nobs}), and upper confidence limit of total bycatch given none 
  observed (\code{ucl}).}
  \item{d}{the negative binomial dispersion index used.}
  \item{cl}{specified confidence level.} 
  \item{target.ucl}{maximum upper confidence limit of bycatch specified.}
  \item{target.oc}{minimum observer coverage for which upper confidence 
  limit of bycatch is (\code{target.ucl}) when none observed.}

Returned invisibly.
}
\description{
\code{plot_uclnegobs} plots upper confidence limit of total bycatch vs 
  observer coverage when no bycatch is observed, given total effort in 
  sets/hauls, negative binomial dispersion index, and confidence level.
}
\details{
Upper confidence limits are based on the probability density function for the 
corresponding Poisson or negative binomial distribution.

Note that unlike \code{plot_cv_obscov}, \code{plot_uclnegobs} is designed 
as a one-step tool. 
  
\strong{Caveat:} \code{plot_uclnegobs} assumes representative observer coverage 
and no hierarchical sources of variance (e.g., vessel- or trip-level variation). 
Violating these assumptions will likely result in negatively biased projections 
of the upper confidence limit of total bycatch given zero observed. More 
conservative projections can be obtained by using higher-level units of effort 
(e.g., \code{te} as number of trips instead of number of sets/hauls).
}