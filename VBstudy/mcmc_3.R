## Author: PGL  Porta Mana
## Created: 2022-09-08T17:03:24+0200
## Last-Updated: 2022-09-17T11:35:19+0200
################
## Test script for VB's data analysis
################

## load customized plot functions
if(!exists('tplot')){source('~/work/tplotfunctions.R')}
##
## Read MCMC seed from command line
mcmcseed = as.integer(commandArgs(trailingOnly=TRUE))[1]
if(is.na(mcmcseed) | (!is.na(mcmcseed) & mcmcseed <=0)){mcmcseed <- 666}
print(paste0('MCMC seed = ',mcmcseed))
##
#### Packages and setup ####
library('data.table')
library('png')
library('foreach')
library('doFuture')
library('doRNG')
registerDoFuture()
print('availableCores:')
print(availableCores())
print('availableCores-multicore:')
print(availableCores('multicore'))
if(file.exists("/cluster/home/pglpm/R")){
    ncores <- availableCores()}else{
    ncores <- 4}
print(paste0('using ',ncores,' cores'))
if(ncores>1){
    if(.Platform$OS.type=='unix'){
        plan(multicore, workers=ncores)
    }else{
        plan(multisession, workers=ncores)
    }
}else{
    plan(sequential)
}
library('nimble')
## NB: also requires library('LaplacesDemon')
#### End custom setup ####

set.seed(707)
## Base name of directory where to save data and plots
baseversion <- '_mcmc3'
nclusters <- 64L
nsamples <- 1024L * 1L # 2L # number of samples AFTER thinning
niter0 <- 1024L * 1L # 3L # iterations burn-in
thin <- 1L #
nstages <- 0L # number of sampling stages beyond burn-in
maincov <- 'Group'
family <- 'Palatino'
ndata <- 400 # ***set this if you want to use fewer data
shuffledata <- TRUE
chooseinitvalues <- TRUE
datafile <- 'Cortical_myelination_faux.csv'
posterior <- TRUE # if set to FALSE it samples and plots prior samples
##
## stagestart <- 0L # set this if continuing existing MC = last saved + 1
##

#### INFORMATION ABOUT THE VARIATES AND THEIR PRIOR PARAMETERS
## Pericalcarine r + h, postcentral r, cuneus r,
variateinfo <- data.table(
    variate=c('Site', 'SurfaceHoles', 'Age', 'Group', 'Sex',
              'lh_WM_pericalcarine',
              'lh_GM_pericalcarine',
              'rh_WM_pericalcarine',
              'rh_GM_pericalcarine',
              'rh_WM_postcentral',
              'rh_GM_postcentral',
              'rh_WM_cuneus',
              'rh_GM_cuneus'
              ),
    type=c('category', 'real', 'integer', 'binary', 'binary',
           'real', 'real', 'real', 'real', 'real', 'real', 'real', 'real'), # 'binary' or 'integer' or 'real'
    min=c(1, 0, 18, 0, 0,
          50, 50, 50, 50, 50, 50, 50, 50 ), # 'binary' should have 0, 'category' 1
    max=c(8, 130, 100, 1, 0,
          100, 100, 100, 100, 100, 100, 100, 100 ),
    precision=c(NA, NA, NA, NA, NA,
          NA, NA, NA, NA, NA, NA, NA, NA )
  ## , # 'binary' should have 1
  ##   mean_mean=c(NA, 40, 30, NA, NA,
  ##               75, 75, 75, 75, 75, 75, 75, 75), # only for 'real' variates, NA for others
  ##   mean_sigma=c(NA, 60, 30, NA, NA,
  ##                20, 20, 20, 20, 20, 20, 20, 20 ),
  ##   sigma_sqrtscale=c(NA, 1, 1, NA, NA,
  ##                    0.0001, 0.0001, 0.0001, 0.0001, 0.0001, 0.0001, 0.0001, 0.0001 )/0.28,
  ##   ## with 1/2, then 1e-6 SD value is ~ 0.28 times the one in sigma_sqrtscale (divide by smaller value to have SD above mininum error)
  ##   sigma_shape=c(NA, 1, 1, NA, NA,
  ##                 1, 1, 1, 1, 1, 1, 1, 1 )/2
)
## Effects of shape parameter:
## 1/8 (broader):
## > testdata <- log10(rinvgamma(n=10^7, shape=1/8, scale=1^2))/2 ; 10^sort(c(quantile(testdata, c(1,7)/8), summary(testdata)))
##         Min.        12.5%      1st Qu.       Median         Mean      3rd Qu. 
## 2.878554e-01 1.937961e+00 3.903828e+00 2.034059e+01 6.641224e+01 3.260648e+02 
##        87.5%         Max. 
## 5.220388e+03 5.266833e+27 
##
## 1/4:
## > testdata <- log10(rinvgamma(n=10^7, shape=1/4, scale=1^2))/2 ; 10^sort(c(quantile(testdata, c(1,7)/8), summary(testdata)))
##         Min.        12.5%      1st Qu.       Median         Mean      3rd Qu. 
## 2.881895e-01 1.274590e+00 1.960271e+00 4.784803e+00 8.283664e+00 1.946374e+01 
##        87.5%         Max. 
## 7.795913e+01 4.670417e+14
##
## 1/2 (narrower):
## > testdata <- log10(rinvgamma(n=10^7, shape=1/2, scale=1^2))/2 ; 10^sort(c(quantile(testdata, c(1,7)/8), summary(testdata)))
##         Min.        12.5%      1st Qu.       Median         Mean      3rd Qu. 
## 2.571008e-01 9.218967e-01 1.229980e+00 2.098062e+00 2.670157e+00 4.440326e+00 
##        87.5%         Max. 
## 8.995125e+00 6.364370e+06 

##
covNames <- variateinfo$variate
covTypes <- variateinfo$type
covMins <- variateinfo$min
covMaxs <- variateinfo$max
names(covTypes) <- names(covMins) <- names(covMaxs) <- covNames
realCovs <- covNames[covTypes=='real']
integerCovs <- covNames[covTypes=='integer']
categoryCovs <- covNames[covTypes=='category']
binaryCovs <- covNames[covTypes=='binary']
#covNames <- c(realCovs, integerCovs, categoryCovs, binaryCovs)
nrcovs <- length(realCovs)
nicovs <- length(integerCovs)
nccovs <- length(categoryCovs)
nbcovs <- length(binaryCovs)
ncovs <- length(covNames)


###########################################
## READ DATA AND SETUP SOME HYPERPARAMETERS
###########################################

alldata <- fread(datafile, sep=',')
if(!all(covNames %in% names(alldata))){print('ERROR: variates missing from datafile')}
alldata <- alldata[, ..covNames]
## shuffle data
if(exists('shuffledata') && shuffledata){alldata <- alldata[sample(1:nrow(alldata))]}
if(!exists('ndata') || is.null(ndata) || is.na(ndata)){ndata <- nrow(alldata)}
alldata <- alldata[1:ndata]
##
dirname <- paste0(baseversion,'-V',length(covNames),'-D',ndata,'-K',nclusters,'-I',nsamples)
dir.create(dirname)

## Normalization and standardization of real variates and calculation of hyperparams

pdff(paste0(dirname,'/densities_variances'),'a4')
variatepars <- NULL
for(avar in covNames){
    dato <- alldata[[avar]]
    if(avar %in% realCovs){
        amedian <- signif(median(dato), log10(IQR(dato)))
        aiqr <- signif(IQR(dato), 2)
        dato <- (dato-amedian)/aiqr
        if(is.na(variateinfo[variate==avar, precision])){
            dmin <- min(diff(sort(unique(dato))))
        }else{
            dmin <- variateinfo[variate==avar, precision]/aiqr
        }
        ##
        qts <- c(2^-14, 0.875)
        fn <- function(p, target){sum((log(qinvgamma(qts, shape=p[1], scale=p[2]))/2 - log(target))^2)}
        resu <- optim(par=c(1/2,1/2), fn=fn, target=c(dmin/2,aiqr))
#        for(i in 1:10){resu <- optim(par=resu$par, fn=fn, target=c(dmin,aiqr))}
        pars <- signif(resu$par, 3)
        ## pars <- c(1/8, (dmin/2/0.28)^2)
        #pars[1] <- 1/8
        vals <- sqrt(qinvgamma(qts, shape=pars[1], scale=pars[2]))
        ## print(avar)
        ## print(c(abs(vals[1] - dmin/2)/(vals[1] + dmin/2)*200,
        ##    abs(vals[2] - aiqr)/(vals[2] + aiqr)*200))
        if(abs(vals[1] - dmin/2)/(vals[1] + dmin/2)*200 > 5 |
           abs(vals[2] - aiqr)/(vals[2] + aiqr)*200 > 5){print(paste0('WARNING ', avar, ': bad parameters'))}
        ## plot
        rg <- diff(range(dato, na.rm=T))
        sgrid <- seq(log10(dmin/2), log10(rg*3), length.out=256)
        vv <- exp(log(10)*2*sgrid)
        tplot(x=sgrid, y=dinvgamma(x=vv, shape=pars[1], scale=pars[2])*vv*2,
              xlab=expression(lg~sigma), ylim=c(0,NA), ylab=NA,
              main=paste0(avar, ': shape = ', pars[1],', scale = ',pars[2]))
        abline(v=log10(c(dmin/2, dmin, IQR(dato), rg, rg*3)), col=yellow, lwd=3)
    }else{
        dmin <- 1L
        amedian <- 0L
        aiqr <- 1L
        pars <- c(NA, NA)
    }
    ##
    variatepars <- rbind(variatepars,
                         c(precision=dmin,
                           median=amedian, IQR=aiqr,
                           min=min(dato, na.rm=T), max=max(dato, na.rm=T),
                           shape=pars[1], scale=pars[2]))
}
rownames(variatepars) <- covNames
dev.off()


#################################
## Setup for Monte Carlo sampling
#################################

if(!exists('stagestart')){stagestart <- 0L}
if(stagestart>0){
    continue <- paste0('_finalstate-R',baseversion,'_',stagestart-1,'-V',length(covNames),'-D',ndata,'-K',nclusters,'-I',nsamples,'--',mcmcseed,'.rds')
}
##

for(obj in c('constants', 'dat', 'inits', 'bayesnet', 'model', 'Cmodel', 'confmodel', 'mcmcsampler', 'Cmcmcsampler')){if(exists(obj)){do.call(rm,list(obj))}}
gc()


## Data (standardized for real variates)
dat <- list()
if(nrcovs>0){ dat$Real=t((t(data.matrix(alldata[, ..realCovs])) - variatepars[realCovs,'median'])/variatepars[realCovs,'IQR'])}
if(nicovs>0){ dat$Integer=data.matrix(alldata[, ..integerCovs])}
if(nccovs>0){ dat$Category=data.matrix(alldata[, ..categoryCovs])}
if(nbcovs>0){ dat$Binary=data.matrix(alldata[, ..binaryCovs])}
##
if(file.exists("/cluster/home/pglpm/R")){
    initial.options <- commandArgs(trailingOnly = FALSE)
    thisscriptname <- sub('--file=', "", initial.options[grep('--file=', initial.options)])
    if(mcmcseed==1){file.copy(from=thisscriptname, to=paste0(dirname,'/script-R',baseversion,'-V',length(covNames),'-D',ndata,'-K',nclusters,'.Rscript'))
    }
}
##
fwrite(cbind(data.table(variate=covNames),variatepars), file=paste0(dirname,'/variateparameters.csv'))

    


####  CONSTANTS, PRIOR PARAMETERS, INITIAL VALUES
source('functions_mcmc.R') # load functions for post-MCMC calculations
##
## In previous versions some statistics of the data were computed
## to decide on the hyperparameters.
## Now this is not done, because wrong in principle
## and because it can lead to silly hyperparameters
##
## Find max integer value in data
if(nicovs > 0){
    ## maximum in data (for inital values)
    maxicovs <- apply(alldata[1:ndata,..integerCovs],2,function(x)max(x, na.rm=T))
    thmaxicovs <- covMaxs[integerCovs] # theoretical maximum
    matrixprobicovs <- matrix(0, nrow=nicovs, ncol=max(thmaxicovs), dimnames=list(integerCovs))
    for(avar in integerCovs){
        matrixprobicovs[avar,1:thmaxicovs[avar]] <- (1:thmaxicovs[avar])/sum(1:thmaxicovs[avar])
    }
}
##
## Find max number of categories in data
if(nccovs > 0){
    ncategories <- max(covMaxs[categoryCovs]) # largest number of categories
    calphapad <- array(0, dim=c(nccovs, ncategories), dimnames=list(categoryCovs,NULL))
    for(avar in categoryCovs){
        calphapad[avar,1:covMaxs[avar]] <- 1
    }
}
## constants
constants <- list(nClusters=nclusters)
if(nrcovs>0){constants$nRcovs <- nrcovs}
if(nicovs>0){constants$nIcovs <- nicovs
    constants$maxIcovs <- ncol(matrixprobicovs)}
if(nccovs>0){constants$nCcovs <- nccovs
    constants$nCategories <- ncategories}
if(nbcovs>0){constants$nBcovs <- nbcovs}
if(posterior){constants$nData <- ndata}
##
initsFunction <- function(){
    c(list(
        qalpha0 = rep(1/nclusters, nclusters) # cluster probabilities
    ),
    if(nrcovs > 0){# real variates
        list(
            meanRmean0 = variatepars[realCovs,'median']*0,
            ## meanRvar0 = (variatepars[realCovs,'IQR']*0+2)^2,
            meanRvar0 = 4*apply(abs(variatepars[realCovs,c('min','max')]),1,max)^2,
            varRscale0 = variatepars[realCovs,'scale'],
            varRshape0 = variatepars[realCovs,'shape']
        )},
    if(nicovs > 0){# integer variates
        list(
            probIa0 = rep(2, nicovs),
            probIb0 = rep(1, nicovs),
            sizeIprob0 = matrixprobicovs*matrixprobicovs,
            sizeI = matrix(maxicovs, nrow=nicovs, ncol=nclusters)
        )},
    if(nccovs > 0){# categorical variates
        list(
            calpha0 = calphapad
        )},
    if(nbcovs > 0){# binary variates
        list(
            probBa0 = rep(1,nbcovs),
            probBb0 = rep(1,nbcovs)
        )},
    if((!chooseinitvalues) & posterior){list(C = rep(1, ndata))}, # cluster occupations: all in one cluster at first
    if(chooseinitvalues & posterior){
        list(q = rdirch(1, alpha=rep(1,nclusters)),
             ## C = rep(1, ndata))
             C = sample(1:nclusters, ndata, replace=TRUE))
        }
)}


##
#### Mathematical form of the long-run frequency distribution
bayesnet <- nimbleCode({
    q[1:nClusters] ~ ddirch(alpha=qalpha0[1:nClusters])
    ##
    for(acluster in 1:nClusters){
        if(nrcovs>0){# real variates
            for(avar in 1:nRcovs){
                meanR[avar,acluster] ~ dnorm(mean=meanRmean0[avar], var=meanRvar0[avar])
                varR[avar,acluster] ~ dinvgamma(shape=varRshape0[avar], scale=varRscale0[avar])
            }
        }
        if(nicovs>0){# integer variates
            for(avar in 1:nIcovs){
                probI[avar,acluster] ~ dbeta(shape1=probIa0[avar], shape2=probIb0[avar])
                sizeI[avar,acluster] ~ dcat(prob=sizeIprob0[avar,1:maxIcovs])
            }
        }
        if(nccovs>0){# category variates
            for(avar in 1:nCcovs){
                probC[avar,acluster,1:nCategories] ~ ddirch(alpha=calpha0[avar,1:nCategories])
            }
        }
        if(nbcovs>0){# binary variates
            for(avar in 1:nBcovs){
                probB[avar,acluster] ~ dbeta(shape1=probBa0[avar], shape2=probBb0[avar])
            }
        }
    }
    ##
    if(posterior){# cluster occupations
        for(adatum in 1:nData){
            C[adatum] ~ dcat(prob=q[1:nClusters])
            ##
            if(nrcovs>0){# real variates
                for(avar in 1:nRcovs){
                    Real[adatum,avar] ~ dnorm(mean=meanR[avar,C[adatum]], var=varR[avar,C[adatum]])
                }
            }
            if(nicovs>0){# integer variates
                for(avar in 1:nIcovs){
                    Integer[adatum,avar] ~ dbinom(prob=probI[avar,C[adatum]], size=sizeI[avar,C[adatum]])
                }
            }
            if(nccovs>0){# category variates
                for(avar in 1:nCcovs){
                    Category[adatum,avar] ~ dcat(prob=probC[avar,C[adatum],1:nCategories])
                }
            }
            if(nbcovs>0){# binary variates
                for(avar in 1:nBcovs){
                    Binary[adatum,avar] ~ dbern(prob=probB[avar,C[adatum]])
                }
            }
        }
    }
})

##
##
timecount <- Sys.time()

if(posterior){
    model <- nimbleModel(code=bayesnet, name='model1', constants=constants, inits=initsFunction(), data=dat, dimensions=list(q=nclusters, meanR=c(nrcovs,nclusters), tauR=c(nrcovs,nclusters), probI=c(nicovs,nclusters), probC=c(nccovs,nclusters,ncategories), probB=c(nbcovs,nclusters), C=ndata) )
}else{
    model <- nimbleModel(code=bayesnet, name='model1', constants=constants, inits=initsFunction(), data=list(), dimensions=list(q=nclusters, meanR=c(nrcovs,nclusters), tauR=c(nrcovs,nclusters), probI=c(nicovs,nclusters), probC=c(nccovs,nclusters,ncategories), probB=c(nbcovs,nclusters)))
}
Cmodel <- compileNimble(model, showCompilerOutput=FALSE)
gc()


##
if(posterior){# Samplers for posterior sampling
    confmodel <- configureMCMC(Cmodel, nodes=NULL,
                               monitors=c('q',
                                          if(nrcovs > 0){c('meanR', 'varR')},
                                          if(nicovs > 0){c('probI', 'sizeI')},
                                          if(nccovs > 0){c('probC')},
                                          if(nbcovs > 0){c('probB')}
                                          ),
                               monitors2=c('C')
                                           )
    ##
    for(adatum in 1:ndata){
        confmodel$addSampler(target=paste0('C[', adatum, ']'), type='categorical')
    }
    for(acluster in 1:nclusters){
        if(nrcovs>0){
            for(avar in 1:nrcovs){
                confmodel$addSampler(target=paste0('meanR[', avar, ', ', acluster, ']'), type='conjugate')
                confmodel$addSampler(target=paste0('varR[', avar, ', ', acluster, ']'), type='conjugate')
            }
        }
        if(nicovs>0){
            for(avar in 1:nicovs){
                confmodel$addSampler(target=paste0('probI[', avar, ', ', acluster, ']'), type='conjugate')
                confmodel$addSampler(target=paste0('sizeI[', avar, ', ', acluster, ']'), type='categorical')
            }
        }
        if(nccovs>0){
            for(avar in 1:nccovs){
                confmodel$addSampler(target=paste0('probC[', avar, ', ', acluster, ', 1:', ncategories, ']'), type='conjugate')
            }
        }
        if(nbcovs>0){
            for(avar in 1:nbcovs){
                confmodel$addSampler(target=paste0('probB[', avar, ', ', acluster, ']'), type='conjugate')
            }
        }
    }
    confmodel$addSampler(target=paste0('q[1:', nclusters, ']'), type='conjugate')
##
}else{# sampler for prior sampling
    confmodel <- configureMCMC(Cmodel, 
                               monitors=c('q',
                                          if(nrcovs>0){c('meanR', 'varR')},
                                          if(nicovs>0){c('probI', 'sizeI')},
                                          if(nccovs>0){c('probC')},
                                          if(nbcovs>0){c('probB')}
                                          ))
}
##
print(confmodel)

mcmcsampler <- buildMCMC(confmodel)
Cmcmcsampler <- compileNimble(mcmcsampler, resetFunctions = TRUE)
gc()

print('Setup time:')
print(Sys.time() - timecount)

##################################################
## Monte Carlo sampler and plots of MC diagnostics
##################################################
for(stage in stagestart+(0:nstages)){
    calctime <- Sys.time()

    print(paste0('==== STAGE ', stage, ' ===='))
    gc()
    if(stage==stagestart){# first sampling stage
        if(exists('continue') && is.character(continue)){# continuing previous
            initsc <- readRDS(paste0(dirname,'/',continue))
            inits0 <- initsFunction()
            for(aname in names(initsc)){inits0[[aname]] <- initsc[[aname]]}
            mcsamples <- runMCMC(Cmcmcsampler, nburnin=0, niter=nsamples*thin, thin=thin, thin2=nsamples*thin, inits=inits0, setSeed=mcmcseed+stage+100)
        }else{# no previous script runs
            inits0 <- initsFunction
            mcsamples <- runMCMC(Cmcmcsampler, nburnin=1, niter=niter0+1, thin=1, thin2=niter0, inits=inits0, setSeed=mcmcseed+stage+100)
        }
    }else{# subsequent sampling stages
        Cmcmcsampler$run(niter=nsamples*thin, thin=thin, thin2=nsamples*thin, reset=FALSE, resetMV=TRUE)
    }
    ##
    mcsamples <- as.matrix(Cmcmcsampler$mvSamples)
    print('Time MCMC:')
    print(Sys.time() - calctime)
    ##
    if(any(is.na(mcsamples))){print('WARNING: SOME NA OUTPUTS')}
    if(any(!is.finite(mcsamples))){print('WARNING: SOME INFINITE OUTPUTS')}
    saveRDS(mcsamples,file=paste0(dirname,'/_mcsamples-R',baseversion,'-V',length(covNames),'-D',ndata,'-K',nclusters,'-I',nrow(mcsamples),'--',stage,'-',mcmcseed,'.rds'))
    ##
    ## save final state of MCMC chain
    finalstate <- as.matrix(Cmcmcsampler$mvSamples2)
    finalstate <- c(mcsamples[nrow(mcsamples),], finalstate[nrow(finalstate),])
    ##
    ## Check how many "clusters" were occupied. Warns if too many
    occupations <- finalstate[grepl('^C\\[', names(finalstate))]
    usedclusters <- length(unique(occupations))
    if(usedclusters > nclusters-5){print('WARNING: TOO MANY CLUSTERS OCCUPIED')}
    print(paste0('OCCUPIED CLUSTERS: ', usedclusters, ' OF ', nclusters))
    saveRDS(finalstate2list(finalstate),file=paste0(dirname,'/_finalstate-R',baseversion,'-V',length(covNames),'-D',ndata,'-K',nclusters,'-I',nrow(mcsamples),'--',stage,'-',mcmcseed,'.rds'))
    ##
    ## SAVE THE PARAMETERS FOR THE TRANSDUCER
    parmList <- mcsamples2parmlist(mcsamples, realCovs, integerCovs, categoryCovs, binaryCovs)
    saveRDS(parmList,file=paste0(dirname,'/_frequencies-R',baseversion,'-V',length(covNames),'-D',ndata,'-K',nclusters,'-I',nrow(parmList$q),'--',stage,'-',mcmcseed,'.rds'))
    ##
    ## Diagnostics
    ## Log-likelihood
    ll <- llSamples(dat, parmList)
    flagll <- FALSE
    if(!posterior && !any(is.finite(ll))){
        flagll <- TRUE
        ll <- rep(0, length(ll))}
    condprobsd <- logsumsamplesF(Y=do.call(cbind,dat)[, maincov, drop=F],
                                 X=do.call(cbind,dat)[, setdiff(covNames, maincov), drop=F],
                                 parmList=parmList, inorder=T)
    condprobsi <- logsumsamplesF(Y=do.call(cbind,dat)[, setdiff(covNames, maincov), drop=F],
                                 X=do.call(cbind,dat)[, maincov, drop=F],               
                                 parmList=parmList, inorder=T)
    ##
    traces <- cbind(loglikelihood=ll, 'mean of direct logprobabilities'=condprobsd, 'mean of inverse logprobabilities'=condprobsi)*10/log(10)/ndata #medians, iqrs, Q1s, Q3s,
    badcols <- foreach(i=1:ncol(traces), .combine=c)%do%{if(all(is.na(traces[,i]))){i}else{NULL}}
    if(!is.null(badcols)){traces <- traces[,-badcols]}
    saveRDS(traces,file=paste0(dirname,'/_probtraces-R',baseversion,'-V',length(covNames),'-D',ndata,'-K',nclusters,'-I',nrow(parmList$q),'--',stage,'-',mcmcseed,'.rds'))
    ##
    if(nrow(traces)>=1000){
        funMCSE <- function(x){LaplacesDemon::MCSE(x, method='batch.means')$se}
    }else{
        funMCSE <- function(x){LaplacesDemon::MCSE(x)}
    }
    diagnESS <- LaplacesDemon::ESS(traces * (abs(traces) < Inf))
    diagnIAT <- apply(traces, 2, function(x){LaplacesDemon::IAT(x[is.finite(x)])})
    diagnBMK <- LaplacesDemon::BMK.Diagnostic(traces, batches=2)[,1]
    diagnMCSE <- 100*apply(traces, 2, function(x){funMCSE(x)/sd(x)})
    diagnStat <- apply(traces, 2, function(x){LaplacesDemon::is.stationary(as.matrix(x,ncol=1))})
    diagnBurn <- apply(traces, 2, function(x){LaplacesDemon::burnin(matrix(x[1:(10*trunc(length(x)/10))], ncol=1))})
    ##
    tracegroups <- list(loglikelihood=1,
                        'main given rest'=2,
                        'rest given main'=3
                        )
    grouplegends <- foreach(agroup=1:length(tracegroups))%do%{
        c( paste0('-- STATS ', names(tracegroups)[agroup], ' --'),
          paste0('min ESS = ', signif(min(diagnESS[tracegroups[[agroup]]]),6)),
          paste0('max IAT = ', signif(max(diagnIAT[tracegroups[[agroup]]]),6)),
          paste0('max BMK = ', signif(max(diagnBMK[tracegroups[[agroup]]]),6)),
          paste0('max MCSE = ', signif(max(diagnMCSE[tracegroups[[agroup]]]),6)),
          paste0('stationary: ', sum(diagnStat[tracegroups[[agroup]]]),'/',length(diagnStat[tracegroups[[agroup]]])),
          paste0('burn: ', signif(max(diagnBurn[tracegroups[[agroup]]]),6))
          )
    }
    colpalette <- c(7,2,1)
    names(colpalette) <- colnames(traces)

    ##
    ## Plot various info and traces
    pdff(paste0(dirname,'/mcsummary2-R',baseversion,'-V',length(covNames),'-D',ndata,'-K',nclusters,'-I',nrow(parmList$q),'--',stage,'-',mcmcseed),'a4')
    matplot(1:2, type='l', col='white', main=paste0('Stats stage ',stage), axes=FALSE, ann=FALSE)
    legendpositions <- c('topleft','topright','bottomleft','bottomright')
    for(alegend in 1:length(grouplegends)){
        legend(x=legendpositions[alegend], bty='n', cex=1.5,
               legend=grouplegends[[alegend]] )
    }
    legend(x='center', bty='n', cex=1,
           legend=c(
               paste0('Occupied clusters: ', usedclusters, ' of ', nclusters),
               paste0('LL: ', signif(mean(ll),3), ' +- ', signif(sd(ll),3)),
               'WARNINGS:',
                    if(any(is.na(mcsamples))){'some NA MC outputs'},
                    if(any(!is.finite(mcsamples))){'some infinite MC outputs'},
                    if(usedclusters > nclusters-5){'too many clusters occupied'},
                    if(flagll){'infinite values in likelihood'}
           ))
    ##
    par(mfrow=c(1,1))
    for(avar in covNames){
        datum <- alldata[[avar]]
        if(avar %in% realCovs){
            rg <- range(datum, na.rm=T)
            rg <- round(c((covMins[avar]+7*rg[1])/8, (covMaxs[avar]+7*rg[2])/8))
##            rg <- c(covMins[avar], covMaxs[avar])
            if(!is.finite(rg[1])){rg[1] <- min(datum, na.rm=T) - IQR(datum, type=8, na.rm=T)}
            if(!is.finite(rg[2])){rg[2] <- max(datum, na.rm=T) + IQR(datum, type=8, na.rm=T)}
            Xgrid <- cbind(seq(rg[1], rg[2], length.out=256))
            histo <- thist(datum, n=32)#-exp(mean(log(c(round(sqrt(length(datum))), length(Xgrid))))))
        }else{
            rg <- range(datum, na.rm=T)
            rg <- round(c((covMins[avar]+7*rg[1])/8, (covMaxs[avar]+7*rg[2])/8))
            Xgrid <- cbind(rg[1]:rg[2])
            histo <- thist(datum, n='i')
        }
        colnames(Xgrid) <- avar
        plotsamples <- samplesF(Y=Xgrid, parmList=parmList, nfsamples=min(64,nrow(mcsamples)), inorder=FALSE, rescale=variatepars)
        ## ymax <- max(quant(apply(plotsamples,2,function(x){quant(x,99/100)}),99/100, na.rm=T), histo$density)
        ## tplot(x=histo$breaks, y=histo$density, col=yellow, lty=1, lwd=1, xlab=avar, ylab='probability density', ylim=c(0, ymax), family=family)
        ymax <- quant(apply(plotsamples,2,function(x){quant(x,99/100)}),99/100, na.rm=T)
        tplot(x=Xgrid, y=plotsamples, type='l', col=paste0(palette()[7], '44'), lty=1, lwd=2, xlab=avar, ylab='probability density', ylim=c(0, ymax), family=family)
        scatteraxis(side=1, n=NA, alpha='88', ext=8, x=datum[sample(1:length(datum),length(datum))]+rnorm(length(datum),mean=0,sd=prod(variatepars[avar,c('precision','IQR')])/16),col=yellow)
    }
    ##
    par(mfrow=c(1,1))
    for(avar in colnames(traces)){
        tplot(y=traces[,avar], type='l', lty=1, col=colpalette[avar],
                main=paste0(avar,
                            '\nESS = ', signif(diagnESS[avar], 3),
                            ' | IAT = ', signif(diagnIAT[avar], 3),
                            ' | BMK = ', signif(diagnBMK[avar], 3),
                            ' | MCSE(6.27) = ', signif(diagnMCSE[avar], 3),
                            ' | stat: ', diagnStat[avar],
                            ' | burn: ', diagnBurn[avar]
                            ),
                ylab=paste0(avar,'/dHart'), xlab='sample', family=family
              )
    }
    dev.off()

    ##
    print('Time MCMC+diagnostics:')
    print(Sys.time() - calctime)
    ##
}

############################################################
## End MCMC
############################################################
plan(sequential)

