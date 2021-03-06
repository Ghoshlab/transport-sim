###################################
### PURPOSE: Simulation Code    ###
### BY: Kevin Josey             ###
###################################

library(snow)

iter <- 1000
n_0 <- c(500, 1000, 10000)
n_1 <- c(200, 1000, 10000)
prob <- 0.5
scen <- c("baseline", "positivity", "interaction", "sparse")

simConditions <- expand.grid(n_0, n_1, prob, scen, stringsAsFactors = FALSE)
names(simConditions) <- c("n_0", "n_1", "prob", "scen")
index <- 1:nrow(simConditions)

## multicore simulation
cl <- makeCluster(3, type = "SOCK")

clusterEvalQ(cl, {
  
  set.seed(07271989)
  
  library(sandwich)
  library(survey)
  
  source("D:/Github/transport-sim/calibrate.R")
  source("D:/Github/transport-sim/tmle.R")
  source("D:/Github/transport-sim/simfun.R")
  
})

clusterExport(cl = cl, list = list("simConditions", "iter"), envir = environment())

start <- Sys.time()

clusterApply(cl, index, function(i) {
  
  dat <- simConditions[i,]
  
  sig2 <- 2
  n_0 <- dat$n_0
  n_1 <- dat$n_1
  prob <- dat$prob
  scen <- dat$scen
  sparse <- scen == "sparse"

  simDat <- replicate(iter, gen_data(n_0 = n_0, n_1 = n_1, prob = prob, sig2 = sig2, scenario = scen))
  
  datFilename <- paste("D:/Dropbox (ColoradoTeam)/JoseyDissertation/Data/transport/simData/", 
                       n_0, n_1, prob, scen, ".RData", sep = "_")
  save(simDat, file = datFilename)
  
  idx <- 1:iter # simulation iteration index
  estList <- sapply(idx, simfit, simDat = simDat, sparse = sparse)
  
  misc_out <- data.frame(n_0 = rep(n_0, times = iter),
                         n_1 = rep(n_1, times = iter),
                         prob = rep(prob, times = iter),
                         scen = rep(scen, times = iter),
                         PATE = do.call(c, simDat[6,]),
                         SATE = do.call(c, simDat[5,]),
                         stringsAsFactors = FALSE)
  
  tau_tmp <- do.call(rbind, estList[1,])
  cp_tmp <- do.call(rbind, estList[2,])
  colnames(tau_tmp) <- c("GLM", "OUT", "TMLE", "MOM", "ENT")
  colnames(cp_tmp) <- c("OM_SATE", "OM_PATE", "ENT_SATE", "ENT_PATE", "IND_PATE")
  
  tau <- data.frame(misc_out, tau_tmp, stringsAsFactors = FALSE)
  cp <- data.frame(misc_out, cp_tmp, stringsAsFactors = FALSE)
  
  tauFilename <- paste("D:/Dropbox (ColoradoTeam)/JoseyDissertation/Data/transport/tauHat/", n_0, n_1, prob, scen, ".RData", sep = "_")
  coverageFilename <- paste("D:/Dropbox (ColoradoTeam)/JoseyDissertation/Data/transport/coverageProb/", n_0, n_1, prob, scen, ".RData", sep = "_")
  
  save(tau, file = tauFilename)
  save(cp, file = coverageFilename)
  
} )

stopCluster(cl)

stop <- Sys.time()
stop - start

### Output

library(ggplot2)
library(gridExtra)

dir_1 <- "D:/Dropbox (ColoradoTeam)/JoseyDissertation/Data/transport/tauHat/"
dir_2 <- "D:/Dropbox (ColoradoTeam)/JoseyDissertation/Data/transport/coverageProb/"

files <- list.files(dir_1)
out_1 <- matrix("", nrow = length(files), ncol = 16)
out_2 <- matrix("", nrow = length(files), ncol = 11)
out_3 <- matrix("", nrow = length(files), ncol = 11)

colnames(out_1) <- c("n_0", "n_1", "prob", "scenario", "PATE", "SATE", "GLM", "OUT","TMLE", "MOM", "ENT",
                     "GLM_conv", "OUT_conv", "TMLE_conv", "MOM_conv", "ENT_conv")
colnames(out_2) <- c("n_0", "n_1", "prob", "scenario", "PATE", "SATE", "ENT_SATE", "ENT_PATE", "OUT_SATE", "OUT_PATE", "IND_PATE")
colnames(out_3) <- c("n_0", "n_1", "prob", "scenario", "PATE", "SATE", "GLM", "OUT", "TMLE", "MOM", "ENT")
j <- 1

for (fdx in files) {
  
  file_est <- paste0(dir_1, fdx)
  file_coverage <- paste0(dir_2, fdx)
  load(file_est)
  load(file_coverage)
  
  lbl <- do.call(c, lapply(tau[1,1:5], as.character))
  
  out_1[j,1:5] <- out_2[j,1:5] <- out_3[j,1:5] <- lbl
  out_1[j,6] <- out_2[j,6] <- out_3[j,6] <- round(mean(tau[,5]), 6) 
  
  conv <- apply(tau[,7:ncol(tau)], 2, function(x) sum(!is.na(x) & !is.infinite(x))/length(x))
  est <- apply(tau[,7:ncol(tau)], 2, function(x) mean(x[!is.infinite(x)], na.rm = TRUE))
  se <- apply(tau[,7:ncol(tau)], 2, function(x) sd(x[!is.infinite(x)], na.rm = TRUE))
  est_se_tmp <- sapply(1:length(est), function(i,...) 
    paste(round(est[i], 2), " (", round(se[i], 2), ")", sep = ""))
  est_se <- c(est_se_tmp, conv)
  
  mse <- apply(tau[,7:ncol(tau)], 2, function(x, PATE) mean((x[!is.infinite(x)] - PATE)^2, na.rm = TRUE), PATE = tau$PATE[1])
  bias <- apply(tau[,7:ncol(tau)], 2, function(x, PATE) mean((x[!is.infinite(x)] - PATE), na.rm = TRUE), PATE = tau$PATE[1])
  mse_bias <- sapply(1:length(mse), function(i,...) 
    paste(round(mse[i], 2), " (", round(bias[i], 2), ")", sep = ""))
  
  coverage <- round(apply(cp[,7:ncol(cp)], 2, mean, na.rm = TRUE), 3)
  
  out_1[j,7:ncol(out_1)] <- est_se
  out_2[j,7:ncol(out_2)] <- coverage
  out_3[j,7:ncol(out_3)] <- mse_bias
  
  j <- j + 1
  
}

load("D:/Dropbox (ColoradoTeam)/JoseyDissertation/Data/transport/tauHat/_500_200_0.5_baseline_.RData")
dat1 <- stack(as.data.frame(tau[,7:ncol(tau)]))
dat1$ind <- factor(dat1$ind, labels = c("Inverse Odds\nof Sampling\nWeights", 
                                        "G-Computation",
                                        "Targeted\nMaximum\nLikelihood\nEstimation",
                                        "Method of\nMoments\nBalancing",
                                        "Entropy\nBalancing"))
p1 <- ggplot(dat1) + 
  geom_boxplot(aes(x = ind, y = values, fill = ind), show.legend = FALSE) + 
  ylab("PATE") +
  ylim(-5, 5)  +
  xlab("") +
  ggtitle("Baseline Conditions") +
  geom_hline(yintercept = -0.1, linetype = 2, show.legend = FALSE) +
  guides(fill =  FALSE) +
  theme_bw() +
  theme(plot.title = element_text(hjust = 0.5))

load("D:/Dropbox (ColoradoTeam)/JoseyDissertation/Data/transport/tauHat/_500_200_0.5_interaction_.RData")
dat2 <- stack(as.data.frame(tau[,7:ncol(tau)]))
dat2$ind <- factor(dat2$ind, labels = c("Inverse Odds\nof Sampling\nWeights", 
                                        "G-Computation",
                                        "Targeted\nMaximum\nLikelihood\nEstimation",
                                        "Method of\nMoments\nBalancing",
                                        "Entropy\nBalancing"))
p2 <- ggplot(dat2) + 
  geom_boxplot(aes(x = ind, y = values, fill = ind)) + 
  ylab("PATE") +
  ylim(-5, 5) +
  xlab("") +
  ggtitle("Unspecified Interaction") +
  geom_hline(yintercept = -0.5, linetype = 2, show.legend = FALSE)  +
  guides(fill =  FALSE) +
  theme_bw() +
  theme(plot.title = element_text(hjust = 0.5))

load("D:/Dropbox (ColoradoTeam)/JoseyDissertation/Data/transport/tauHat/_500_200_0.5_positivity_.RData")
dat3 <- stack(as.data.frame(tau[,7:ncol(tau)]))
dat3$ind <- factor(dat3$ind, labels = c("Inverse Odds\nof Sampling\nWeights", 
                                        "G-Computation",
                                        "Targeted\nMaximum\nLikelihood\nEstimation",
                                        "Method of\nMoments\nBalancing",
                                        "Entropy\nBalancing"))
p3 <- ggplot(dat3) + 
  geom_boxplot(aes(x = ind, y = values, fill = ind)) + 
  ylab("PATE") +
  ylim(-5, 5)  +
  xlab("") +
  ggtitle("Positivity Violation") +
  geom_hline(yintercept = -0.2, linetype = 2, show.legend = FALSE) +
  guides(fill =  FALSE) +
  theme_bw() +
  theme(plot.title = element_text(hjust = 0.5))

load("D:/Dropbox (ColoradoTeam)/JoseyDissertation/Data/transport/tauHat/_500_200_0.5_sparse_.RData")
dat4 <- stack(as.data.frame(tau[,7:ncol(tau)]))
dat4$ind <- factor(dat4$ind, labels = c("Inverse Odds\nof Sampling\nWeights", 
                                         "G-Computation",
                                         "Targeted\nMaximum\nLikelihood\nEstimation",
                                         "Method of\nMoments\nBalancing",
                                         "Entropy\nBalancing"))
p4 <- ggplot(dat4) + 
  geom_boxplot(aes(x = ind, y = values, fill = ind)) + 
  ylab("PATE") +
  ylim(-5, 5)  +
  xlab("") +
  ggtitle("Sparse Conditions") +
  geom_hline(yintercept = -0.1, linetype = 2, show.legend = FALSE) +
  guides(fill =  FALSE) +
  theme_bw() +
  theme(plot.title = element_text(hjust = 0.5))

png("D:/Dropbox (ColoradoTeam)/JoseyDissertation/Output/transport/Figures/ATE_plot.png", 
    width = 3000, 
    height = 3000,
    res = 300, 
    units = "px")

grid.arrange(p1, p2, p3, p4, ncol = 2, nrow = 2)

dev.off()


# plot outcomes

# png("D:/Dropbox (ColoradoTeam)/Projects/VADT/Output/Figures/ATE_plot.png", 
#     width = 1000, 
#     height = 1000,
#     res = 100, 
#     units = "px")
# 
# grid.arrange(p1, p2, p3, p4, ncol = 2, nrow = 2)
# 
# dev.off()

out_1 <- subset(data.frame(out_1), n_1 != 10000 & n_0 != 10000, select = -c(prob))
out_1[,1:2] <- apply(out_1[,1:2], 2, as.numeric)
out_1 <- out_1[order(out_1$n_0, out_1$n_1),]

out_2 <- subset(data.frame(out_2), scenario == "baseline" & n_1 != 200, select = -c(scenario, PATE, SATE, prob))
out_2[,1:2] <- apply(out_2[,1:2], 2, as.numeric)
out_2 <- out_2[order(out_2$n_0, out_2$n_1),]

out_3 <- subset(data.frame(out_3), n_1 != 10000 & n_0 != 10000, select = -c(prob))
out_3[,1:2] <- apply(out_3[,1:2], 2, as.numeric)
out_3 <- out_3[order(out_3$n_0, out_3$n_1),]

filename1 <- "D:/Dropbox (ColoradoTeam)/JoseyDissertation/Output/transport/Tables/estimates.csv"
filename2 <- "D:/Dropbox (ColoradoTeam)/JoseyDissertation/Output/transport/Tables/coverageProbs.csv"
filename3 <- "D:/Dropbox (ColoradoTeam)/JoseyDissertation/Output/transport/Tables/mse_bias.csv"

write.csv(out_1, file = filename1)
write.csv(out_2, file = filename2)
write.csv(out_3, file = filename3)
