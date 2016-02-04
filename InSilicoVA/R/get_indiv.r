#' Get individual COD probabilities from InSilicoVA Model Fits
#' 
#' This function calculates individual probabilities for each death and provide posterior credible intervals for each estimates. The default set up is to calculate the 95% C.I. when running the inSilicoVA model. If a different C.I. is desired after running the model, this function provides faster re-calculation without refitting the model.
#' 
#' 
#' @param object Fitted \code{"insilico"} object.
#' @param CI Confidence interval for posterior estimates.
#' @param java_option Option to initialize java JVM. Default to ``-Xmx1g'', which sets the maximum heap size to be 1GB.
#' @param \dots Not used.
#' @return
#' \item{mean}{ individual mean COD distribution matrix.} 
#' \item{median}{ individual median COD distribution matrix.} 
#' \item{lower}{ individual lower bound for each COD probability.} 
#' \item{upper}{ individual upper bound for each COD probability.} 

#' @author Zehang Li, Tyler McCormick, Sam Clark
#' 
#' Maintainer: Zehang Li <lizehang@@uw.edu>
#' @seealso \code{\link{insilico}}, \code{\link{plot.insilico}}
#' @references Tyler H. McCormick, Zehang R. Li, Clara Calvert, Amelia C.
#' Crampin, Kathleen Kahn and Samuel J. Clark Probabilistic cause-of-death
#' assignment using verbal autopsies, \emph{arXiv preprint arXiv:1411.3042}
#' \url{http://arxiv.org/abs/1411.3042} (2014)
#' @examples
#' \dontrun{
#' data(RandomVA1)
#' fit1<- insilico(RandomVA1, subpop = NULL,  
#'                 length.sim = 1000, burnin = 500, thin = 10 , seed = 1,
#'                 auto.length = FALSE)
#' summary(fit1, id = "d199")
#' 
#' # The following script updates credible interval for individual 
#' # probabilities to 90%
#' indiv.new <- get.indiv(fit1, CI = 0.9)
#' fit1$indiv.prob.lower <- indiv.new$lower
#' fit1$indiv.prob.upper <- indiv.new$upper
#' fit1$indiv.CI <- 0.9
#' summary(fit1, id = "d199")
#' }
#' @export get.indiv
get.indiv <- function(object, CI = 0.95, java_option = "-Xmx1g", ...){
	if(is.null(java_option)) java_option = "-Xmx1g"
	options( java.parameters = java_option )
	id <- object$id
	obj <- .jnew("sampler/InsilicoSampler2")

	# 3d array of csmf to be Nsub * Nitr * C
	if(is.null(object$subpop)){
		csmf <- array(0, dim = c(1, dim(object$csmf)[1], dim(object$csmf)[2]))
		csmf[1, , ] <- object$csmf
		subpop <- rep(as.integer(1), length(object$id))
	}else{
		csmf <- array(0, dim = c(length(object$csmf), dim(object$csmf[[1]])[1], dim(object$csmf[[1]])[2]))
		for(i in 1:length(object$csmf)){
			csmf[i, , ] <- object$csmf[[i]]
		}
		subpop <- as.integer(match(object$subpop, names(object$csmf)))
	}	

	if(object$external){
		csmf <- csmf[, , -object$external.causes, drop = FALSE]
	}

	csmf.j <- .jarray(csmf, dispatch = TRUE)
	data.j <- .jarray(object$data, dispatch = TRUE)
	subpop.j <- .jarray(subpop, dispatch = TRUE)
	impossible.j <- .jarray(object$impossible.causes, dispatch = TRUE)
	# get condprob to be Nitr * S * C array
	if(object$updateCondProb == FALSE){
		condprob <- array(0, dim = c(1, dim(object$probbase)[1], dim(object$probbase)[2]))
		condprob[1, , ] <- object$probbase
	}else{
		if(object$keepProbbase.level){
			condprob <- array(0, dim = c(dim(object$conditional.probs)[1], dim(object$probbase)[1], dim(object$probbase)[2]))
			for(i in 1:dim(condprob)[1]){
				#fix for interVA probbase
				object$probbase[object$probbase == "B -"] <- "B-"
				object$probbase[object$probbase == ""] <- "N"
				
				temp <- object$conditional.probs[i, match(object$probbase, colnames(object$conditional.probs))]
				condprob[i, , ] <- matrix(as.numeric(temp), 
											dim(object$probbase)[1], 
										    dim(object$probbase)[2])
			}
		}else{
			condprob <- object$conditional.probs
		}
	}
	condprob.j <- .jarray(condprob, dispatch = TRUE)

	cat("Calculating individual probabilities...\n")
	indiv  <- .jcall(obj, "[[D", "IndivProb", 
					 data.j, impossible.j, csmf.j, subpop.j, condprob.j, 
					 (1 - CI)/2, 1-(1-CI)/2)

	indiv <- do.call(rbind, lapply(indiv, .jevalArray))
	data("causetext", envir = environment())
	causetext<- get("causetext", envir  = environment())
	
	match.cause <- pmatch(causetext[, 1],  colnames(object$probbase))
	index.cause <- order(match.cause)[1:sum(!is.na(match.cause))]
	colnames(indiv) <- causetext[index.cause, 2]

	K <- dim(indiv)[1] / 4


	## add back all external cause death 41:51 in standard VA
	if(object$external){
		external.causes <- object$external.causes
		C0 <- dim(indiv)[2]
		ext.flag <- apply(object$indiv.prob[, external.causes], 1, sum)
		ext.probs <- object$indiv.prob[which(ext.flag == 1), ]

		indiv <- cbind(indiv[, 1:(external.causes[1] - 1)], 
			          matrix(0, dim(indiv)[1], length(external.causes)), 
			          indiv[, external.causes[1]:C0])
		colnames(indiv) <- colnames(object$indiv.prob)
		id.out <- c(id[match(rownames(object$data), id)], id[which(ext.flag == 1)])
	}else{
		id.out <- id
		ext.probs <- NULL
	}

	mean <- rbind(indiv[1:K, ], ext.probs)
	median <- rbind(indiv[(K+1):(2*K), ], ext.probs)
	lower <- rbind(indiv[(2*K+1):(3*K), ], ext.probs)
	upper <- rbind(indiv[(3*K+1):(4*K), ], ext.probs)

	rownames(mean) <- rownames(median) <- rownames(lower) <- rownames(upper) <- id.out
	return(list(mean = mean, median = median, 
				lower = lower, upper = upper))
}