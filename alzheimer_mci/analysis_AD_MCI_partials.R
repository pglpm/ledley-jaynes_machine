#### Exploration of results

library('inferno')

## How many parallel cores for the calculations
parallel <- 4

## Name of directory where the "learning" has been saved
partial <- 30
learntdir <- paste0('output_partial_', partial)
##
metadata <- read.csv(file.path(learntdir, 'metadata.csv'), na.strings = '')
## dat <- read.csv(paste0('partialdata_', partial, '.csv'), na.strings = '')
dat <- read.csv('ingrid_dataupd_nogds6.csv', na.strings = '')

ravltimRange <- seq(
    min(dat$RAVLT_im, na.rm = TRUE),
    max(dat$RAVLT_im, na.rm = TRUE),
    by = 1)
##
Y <- data.frame(RAVLT_im = ravltimRange)
X <- data.frame(Subgroup = c('sMCI', 'cAD'))
##
ravltimProb <- Pr(Y = Y, X = X, learnt = learntdir)
##
plot(ravltimProb)
