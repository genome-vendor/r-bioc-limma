##  CAMERA.R

interGeneCorrelation <- function(y, design)
#	Estimate variance-inflation factor for means of correlated genes
#	Gordon Smyth and Di Wu
#	Created 2007.  Last modified 11 Feb 2012
{
	m <- nrow(y)
	qrdesign <- qr(design)
	y <- qr.qty(qrdesign, t(y))[-(1:qrdesign$rank),]
#	Gives same result as the following
#	ny <- t(y) / sqrt(colSums(y^2))
#	cormatrix <- tcrossprod(ny)
#	correlation <- mean(cormatrix[lower.tri(cormatrix)])
#	1+correlation*(n-1)
	y <- t(y) / sqrt(colMeans(y^2))
	vif <- m * mean(colMeans(y)^2)
	correlation <- (vif-1)/(m-1)
	list(vif=vif,correlation=correlation)
}

camera <- function(y,index,design=NULL,contrast=ncol(design),weights=NULL,use.ranks=FALSE,allow.neg.cor=TRUE,trend.var=FALSE,sort=TRUE)
UseMethod("camera")

camera.EList <- function(y,index,design=NULL,contrast=ncol(design),weights=NULL,use.ranks=FALSE,allow.neg.cor=TRUE,trend.var=FALSE,sort=TRUE)
#	Gordon Smyth
#  Created 4 Jan 2013.  Last modified 22 Jan 2013
{
	if(is.null(design)) design <- y$design
	if(is.null(weights)) weights <- y$weights
	y <- y$E
	camera(y=y,index=index,design=design,contrast=contrast,weights=weights,use.ranks=use.ranks,allow.neg.cor=allow.neg.cor,trend.var=trend.var,sort=sort)
}

camera.MAList <- function(y,index,design=NULL,contrast=ncol(design),weights=NULL,use.ranks=FALSE,allow.neg.cor=TRUE,trend.var=FALSE,sort=TRUE)
#	Gordon Smyth
#  Created 4 Jan 2013.  Last modified 22 Jan 2013
{
	if(is.null(design)) design <- y$design
	if(is.null(weights)) weights <- y$weights
	y <- y$M
	camera(y=y,index=index,design=design,contrast=contrast,weights=weights,use.ranks=use.ranks,allow.neg.cor=allow.neg.cor,trend.var=trend.var,sort=sort)
}

camera.default <- function(y,index,design=NULL,contrast=ncol(design),weights=NULL,use.ranks=FALSE,allow.neg.cor=TRUE,trend.var=FALSE,sort=TRUE)
#	Competitive gene set test allowing for correlation between genes
#	Gordon Smyth and Di Wu
#  Created 2007.  Last modified 22 Jan 2013
{
#	Check y
	y <- as.matrix(y)
	G <- nrow(y)
	n <- ncol(y)

#	Check index
	if(!is.list(index)) index <- list(set1=index)

#	Check design
	if(is.null(design)) stop("no design matrix")
	p <- ncol(design)
	df.residual <- n-p
	df.camera <- min(df.residual,G-2)

#	Check weights
	if(!is.null(weights)) {
		if(any(weights<=0)) stop("weights must be positive")
		if(length(weights)==n) {
			sw <- sqrt(weights)
			y <- t(t(y)*sw)
			design <- design*sw
			weights <- NULL
		}
	}
	if(!is.null(weights)) {
		if(length(weights)==G) weights <- matrix(weights,G,n)
		weights <- as.matrix(weights)
		if(any( dim(weights) != dim(y) )) stop("weights not conformal with y")
	}

#	Reform design matrix so that contrast of interest is last column
	if(is.character(contrast)) {
		contrast <- which(contrast==colnames(design))
		if(length(contrast)==0) stop("coef ",contrast," not found")
	}
	if(length(contrast)==1) {
		j <- c((1:p)[-contrast], contrast)
		if(contrast<p) design <- design[,j]
	} else {
		QR <- qr(contrast)
		design <- t(qr.qty(QR,t(design)))
		if(sign(QR$qr[1,1]<0)) design[,1] <- -design[,1]
		design <- design[,c(2:p,1)]
	}

#	Compute effects matrix
	if(is.null(weights)) {
		QR <- qr(design)
		if(QR$rank<p) stop("design matrix is not of full rank")
		effects <- qr.qty(QR,t(y))
		unscaledt <- effects[p,]
		if(QR$qr[p,p]<0) unscaledt <- -unscaledt
	} else {
		effects <- matrix(0,n,G)
		unscaledt <- rep(0,n)
		sw <- sqrt(weights)
		yw <- y*sw
		for (g in 1:G) {
			xw <- design*sw[g,]
			QR <- qr(xw)
			if(QR$rank<p) stop("weighted design matrix not of full rank for gene ",g)
			effects[,g] <- qr.qty(QR,yw[g,])
			unscaledt[g] <- effects[p,g]
			if(QR$qr[p,p]<0) unscaledt[g] <- -unscaledt[g]
		}
	}

#	Standardized residuals
	U <- effects[-(1:p),,drop=FALSE]
	sigma2 <- colMeans(U^2)
	U <- t(U) / sqrt(sigma2)

#	Moderated t
	if(trend.var) A <- rowMeans(y) else A <- NULL
	sv <- squeezeVar(sigma2,df=df.residual,covariate=A)
	modt <- unscaledt / sqrt(sv$var.post)
	df.total <- min(df.residual+sv$df.prior, G*df.residual)
	Stat <- zscoreT(modt, df=df.total)

#	Global statistics
	meanStat <- mean(Stat)
	varStat <- var(Stat)

	nsets <- length(index)
	tab <- matrix(0,nsets,5)
	rownames(tab) <- names(index)
	colnames(tab) <- c("NGenes","Correlation","Down","Up","TwoSided")
	for (i in 1:nsets) {
		iset <- index[[i]]
		StatInSet <- Stat[iset]
		m <- length(StatInSet)
		m2 <- G-m
		if(m>1) {
			Uset <- U[iset,,drop=FALSE]
			vif <- m * mean(colMeans(Uset)^2)
			correlation <- (vif-1)/(m-1)
		} else {
			vif <- 1
			correlation <- NA
		}

		tab[i,1] <- m
		tab[i,2] <- correlation
		if(use.ranks) {
			if(!allow.neg.cor) correlation <- max(0,correlation)
			tab[i,3:4] <- rankSumTestWithCorrelation(iset,statistics=Stat,correlation=correlation,df=df.camera)
		} else {	
			if(!allow.neg.cor) vif <- max(1,vif)
			meanStatInSet <- mean(StatInSet)
			delta <- G/m2*(meanStatInSet-meanStat)
			varStatPooled <- ( (G-1)*varStat - delta^2*m*m2/G ) / (G-2)
			two.sample.t <- delta / sqrt( varStatPooled * (vif/m + 1/m2) )
			tab[i,3] <- pt(two.sample.t,df=df.camera)
			tab[i,4] <- pt(two.sample.t,df=df.camera,lower.tail=FALSE)
		}
	}
	tab[,5] <- 2*pmin(tab[,3],tab[,4])

#	New column names (Jan 2013)
	tab <- data.frame(tab,stringsAsFactors=FALSE)
	Direction <- rep.int("Up",nsets)
	Direction[tab$Down < tab$Up] <- "Down"
	tab$Direction <- Direction
	tab$PValue <- tab$TwoSided
	tab$Down <- tab$Up <- tab$TwoSided <- NULL

#	Add FDR
	if(nsets>1) tab$FDR <- p.adjust(tab$PValue,method="BH")

#	Sort by p-value
	if(sort && nsets>1) {
		o <- order(tab$PValue)
		tab <- tab[o,]
	}

	tab
}
