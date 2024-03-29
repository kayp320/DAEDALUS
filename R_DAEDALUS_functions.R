################################################################################
#RJ notes 19/1/24
# I require real from eigen
# rename F to Fmat as F=FALSE
# rename t to day as t() is the transpose function

################################################################################
#All functions required to run DAEDALUS for p2


################################################################################
#Launch simulation:

p2Run <- function(data, dis, Xit, p2) {
  
  adInd <- 3
  lx <- length(data$obj) # 45 sectors
  ln <- length(data$NNs) # 49 (45 sectors + 4 age groups)
  int <- data$int # 5 time periods
  NNbar <- data$NNs # Total workforce in each sector if economy is fully open
  XitMat <- Reshape(Xit, lx, int)
  WitMat <- XitMat ^ (1 / data$alp)
  WitMat[data$EdInd, ] <- XitMat[data$EdInd, ]
  NNvec <- matrix(rep(NNbar[1:lx], int), lx, int) * WitMat #Actually a matrix - each column a vector NN
  NNworkSum <- colSums(NNvec)
  NNvec <- rbind(NNvec, matrix(rep(NNbar[(lx + 1):ln], int), (ln-lx), int))
  NNvec[lx + adInd, ] <- sum(NNbar[c(1:lx, lx + adInd)]) - NNworkSum
  data$NNvec <- NNvec
  
  Dvec <- array(0, dim = c(ln, ln, int))
  for (i in 1:int) {
    Dtemp <- p2MakeDs(data, NNvec[, i], XitMat[, i], data$hw[i, ])
    #Dtemp <- Dtemp$Dout
    Dvec[,, i] <- Dtemp$Dout
  }
  data$Dvec <- Dvec
  data$lx <- lx
  
  #data <- p2SimVax(data, NNvec, Dvec, dis, NNvec[, 1], WitMat, p2) #xx S0 moved to p2SimVax
  funOut <- p2SimVax(data, NNvec, Dvec, dis, WitMat, p2)
  
  return(funOut)
}

################################################################################
#Simulation:

#p2SimVax <- function(data, NNvec, Dvec, dis, S0, WitMat, p2) {
p2SimVax <- function(data, NNvec, Dvec, dis, WitMat, p2) {
  
  S0 <- NNvec[, 1]
  betamod <- 1
  
  ntot <- length(data$NNs)
  adInd <- 3
  lx <- data$lx
  NNbar <- NNvec[, 1]
  sumWorkingAge <- sum(NNbar[c(1:lx, lx + 3)])
  nc <- 20
  zn <- rep(0, ntot)
  znMat <- matrix(zn, 1, ntot)
  y0 <- c(S0, rep(zn, 6), NNbar - S0, rep(zn, nc - 9), S0)
  Tout <- data$tvec[1]
  Iout <- znMat
  Isaout <- znMat
  Issout <- znMat
  Insout <- znMat
  Hout <- znMat
  Dout <- znMat
  Wout <- matrix(0, 0, lx)#matrix(0, nrow = 0, ncol = lx)
  hwout <- matrix(0, 0, lx)#matrix(0, nrow = 0, ncol = lx)
  poutout <- 0
  betamodout <- 1
  Vout <- znMat
  rout <- 0
  
  # Loop
  for (i in 1:data$int) {
    
    t0 <- data$tvec[i]
    tend <- data$tvec[i + 1]
    Wit <- WitMat[, i]
    NNfeed <- NNvec[, i]
    NNfeed[NNfeed == 0] <- 1
    D <- Dvec[,, i]
    
    # Vaccination roll out by sector
    
    NNnext <- NNvec[, i]  # total population in a given period i
    NNnext[lx + c(1, 2)] <- 1
    NNnext[c(1:lx, lx + 3)] <- NNnext[c(1:lx, lx + 3)] / sumWorkingAge
    NNnext[ntot] <- 1 # Retired age population
    
    p2$ratep1 <- NNnext * c(rep(p2$aratep1[3], lx), p2$aratep1)
    p2$ratep2 <- NNnext * c(rep(p2$aratep2[3], lx), p2$aratep2)
    p2$ratep3 <- NNnext * c(rep(p2$aratep3[3], lx), p2$aratep3)
    p2$ratep4 <- NNnext * c(rep(p2$aratep4[3], lx), p2$aratep4)
    
    #browser(expr = {i==2})
    
    # Solve the ODE system
    #res <- ode(y = y0,
    #           day = c(t0, tend),
    #           func = p2Model,
    #           parms = p2)
    #xx David: I *think* the above was a placeholder
    res <- integr8(data, NNfeed, D, i, t0, tend, dis, y0, p2, betamod)
    y0 <- res$y0new
    
    # Extract the results
    end <- length(res$tout)
    Tout <- c(Tout, res$tout[2:end])
    Iout <- rbind(Iout, res$Iclass[2:end, ])
    Isaout <- rbind(Isaout, res$Isaclass[2:end, ])
    Issout <- rbind(Issout, res$Issclass[2:end, ])
    Insout <- rbind(Insout, res$Insclass[2:end, ])
    Hout <- rbind(Hout, res$Hclass[2:end, ])
    Dout <- rbind(Dout, res$Dclass[2:end, ])
    
    # Calculate the workforce
    W <- t(matrix(rep(Wit, end), lx, end)) * matrix(1, end, lx)
    Wout <- rbind(Wout, W[1:(nrow(W) - 1), ])
    
    # worker hours
    hw <- t(matrix(rep(data$hw[i, ], end), lx, end)) * matrix(1, end, lx)
    hwout <- rbind(hwout, hw[1:(nrow(W) - 1), ]) 
    
    # vaccination coverage
    poutout <- c(poutout, res$pout[2:end])
    
    # transmission modifier
    betamodout <- c(betamodout, res$betamod[2:end])
    
    # vaccination uptake
    Vout <- rbind(Vout, res$Vclass[2:end, ])
    
    # Update the workforce and worker hours for the next time period
    
    if (i < data$int) {
      
      y0 <- matrix(y0, ntot, nc)
      
      # Calculate the number of extra workers needed next period
      Xh2w <- NNvec[1:lx, i + 1] - NNvec[1:lx, i]
      Xw2h <- -Xh2w
      
      # Set the negative elements of Xh2w and Xw2h to zero
      Xh2w[Xh2w < 0] <- 0
      Xw2h[Xw2h < 0] <- 0
      
      # Calculate the proportion of extra workers needed next period by sector
      Xh2w <- Xh2w / NNvec[lx + adInd, i]
      
      # Set the elements of Xh2w to zero for sectors that have no workers
      Xh2w[NNvec[lx + adInd, i] == 0] <- 0
      
      # Calculate the proportion of workers not needed next period by sector
      Xw2h <- Xw2h / NNvec[1:lx, i]
      
      # Set the elements of Xw2h to zero for sectors that have no workers
      Xw2h[NNvec[1:lx, i] == 0] <- 0
      
      # Calculate the number of people to be put at home
      y0w2h <- y0[1:lx, ] * matrix(rep(Xw2h, nc), nrow = lx, ncol = nc)
      
      # Add the people to be put at home to the non-working population and subtract them from the workforce
      y0w2h <- rbind(-y0w2h, colSums(y0w2h))
      
      # Calculate the number of people to be put at work
      #y0h2w <- kronecker.prod(y0[lx + adInd, ], Xh2w) #xx
      y0h2w <- t(matrix(rep(y0[lx + adInd, ], lx), nc, lx)) * matrix(rep(Xh2w, nc), lx, nc)
      
      # Add the people to be put at work to the workforce and subtract them from the non-working population
      y0h2w <- rbind(y0h2w, -colSums(y0h2w))
      
      # Update the y0 vector
      y0[c(1:lx, lx+adInd), ] <- y0[c(1:lx, lx+adInd), ] + y0w2h + y0h2w
      #y0[lx + adInd, ] <- y0[lx + adInd, ] + y0h2w #xx
      
      y0 = c(y0)
    }
    
  }
  
  # Outputs
  
  Wout <- rbind(Wout, Wout[nrow(Wout), ])
  
  hwout <- rbind(hwout, hwout[nrow(hwout), ])

  # Create a new matrix `g` that stores results of the ODE 
  g <- cbind(Tout, Wout, hwout, Isaout, Issout, Insout, Hout, Dout, Vout, betamodout)
  
  f <- cbind(Tout,
             rowSums(Iout),
             rowSums(Hout),
             rowSums(Dout),
             poutout,
             betamodout,
             Vout[,(lx + 1)],
             Vout[,(lx + 2)],
             rowSums(Vout[, c(1:lx, lx + 3)]),
             Vout[,(lx + 4)],
             Dout[,(lx + 1)],
             Dout[,(lx + 2)],
             rowSums(Dout[, c(1:lx, lx + 3)]),
             Dout[,(lx + 4)])
  
  return(list(data = data, f = f, g = g))
  
}

################################################################################
#Integration:

integr8 <- function(data, NN0, D, i, t0, tend, dis, y0, p2, betamod) {
  
  ntot <- length(data$NNs)
  #params <- list(data = data, NN0 = NN0, D = D, i = i, dis = dis, p2 = p2, b0 = 2.197, b1 = 0.1838, b2 = -1.024)
  #xx Copied from inside function "odes":
  params <- list(data = data, NN0 = NN0, D = D, i = i, dis = dis, p2 = p2, ntot = length(data$NNs), 
                 b0 = 2.197, b1 = 0.1838, b2 = -1.024, phi = 1, betamod = betamod)
################################
  # Define the ODE function
  toSolve  <- {function(day, y, params) odes(y, day, params=params)}#deSolve/ode
  
  yout <- ode(y = y0, times = seq(t0, tend, by = 1), toSolve, params, method="ode45")#xx Time intervals different to MATLAB code
  
  tout <- yout[, "time"]
  y0new <- tail(yout, n = 1)[, -1]
  yout <- as.matrix(yout[, -1])
  ################################
  
  # Output
  Iclass <- yout[, (2*ntot + 1):(3*ntot)] + yout[, (3*ntot + 1):(4*ntot)]
                      + yout[, (4*ntot + 1):(5*ntot)] + yout[, (5*ntot + 1):(6*ntot)]
                      + yout[, (11*ntot + 1):(12*ntot)] + yout[, (12*ntot + 1):(13*ntot)]
                      + yout[, (13*ntot + 1):(14*ntot)] + yout[, (14*ntot + 1):(15*ntot)]
  Isaclass <- yout[, (3*ntot+ 1): (4*ntot)] + yout[, (12*ntot + 1): (13*ntot) ]
  Issclass <- yout[, (5*ntot+1): (6*ntot)] + yout[, (14*ntot+1) : (15*ntot) ]
  Insclass <- yout[, (4*ntot+1): (5*ntot)] + yout[, (13*ntot+1) : (14*ntot) ] 
  Hclass   <- yout [,  (6*ntot+1): (7*ntot)] + yout[, (15*ntot+1) :(16*ntot) ]
  Dclass   <- yout [, (17*ntot+1) : (18*ntot) ]
  Vclass   <-  yout [, (18*ntot+1) : (19*ntot) ]

  # Time - dependent parameters
  
  occ <- pmax(1, rowSums(Hclass)) #Total occupancy (day)
  Hmax <- p2$Hmax
  SHmax <- p2$SHmax
  th0 <- pmax(1, 1 + 1.87 * ((occ - Hmax) / (SHmax - Hmax)))
  
  locc <- length(occ)
  pd <- pmin(th0 * t(matrix(rep(dis$pd, locc), ntot, locc)), 1) 
  
  Th <- (1 - pd) * dis$Threc + pd * dis$Thd
  mu <- pd / Th
  ddk <- 10^5 * rowSums(mu * Hclass) / sum(NN0)
  
  sd_fun <- function(l, b, x) {
    c((l - b) + (1 - l + b) * (1 + ((l - 1) / (1 - l + b))))^(x / 10) #xx c() added
  }
  
  # betamod
  if (i == 1) {
    betamod <- rep(1, length(occ))
  } else if (i %in% data$imand) {
    betamod <- pmin(pmax(p2$sdl, sd_fun(p2$sdl, p2$sdb, ddk)), pmax(p2$sdl, sd_fun(p2$sdl, p2$sdb, 2)))
  } else {
    betamod <- pmax(p2$sdl, sd_fun(p2$sdl, p2$sdb, ddk))
  }
  
  S <- yout[, 1:ntot]
  Sn <- yout[, (19*ntot + 1):(20*ntot)]
  Ins <- yout[, (4*ntot + 1):(5*ntot)]
  Iss <- yout[,(5*ntot+1): (6*ntot)]
  Insv1 <- yout[,(13*ntot+1):(14*ntot)]
  Issv1 <- yout[,(14*ntot+1):(15*ntot)]
  H     <- yout[,(6*ntot+1):(7*ntot)]
  Hv1   <- yout[, (15*ntot+1):(16*ntot)]
  
  
  amp <- (Sn + (1 - dis$heff) * (S - Sn)) / S
  ph <- amp * dis$ph
  Ts <- (1 - ph) * dis$Tsr + ph * dis$Tsh
  g3 <- (1 - pd) / Th
  h <- ph / Ts
  h_v1 <- dis$h_v1
  dur <- p2$dur
  qh <- ph / (Ts - dur)
  qh_v1 <- p2$qh_v1  
  
  # Hospitalisation
  Hdot <- (h * Ins) + (qh * Iss) - ((g3 + mu) * Hclass)
  Hv1dot <- h_v1 * Insv1 + qh_v1 * Issv1 - (g3 + mu) * Hv1
  occdot <- rowSums(Hdot + Hv1dot)
  r <- occdot/occ
  
  Ina <- yout[, (2*ntot+1):(3*ntot)]
  Isa <- yout[, (3*ntot+1):(4*ntot)]
  Inav1 <- yout[, (11*ntot+1):(12*ntot)]
  Isav1 <- yout[, (12*ntot+1):(13*ntot)]
  
  Ip  <-  10^5*rowSums(Ina+Ins+Isa+Iss+Inav1+Insv1+Isav1+Issv1)/sum(NN0)
  trate <- c(p2$trate)
  t_tit <- c(p2$t_tit)
  
  if (i != 5){
      pout <- as.numeric(Ip<trate) * (1 / (1 + exp(params$b0 + params$b1 * Ip + params$b2 * log10(trate)))) / p2$dur +
        as.numeric(Ip >= trate) * pmin(1 / (1 + exp(params$b0 + params$b1 * Ip + params$b2 * log10(trate))), trate / 10^5) / p2$dur 
      pout <- pout*as.numeric(tout > t_tit & tout < p2$end)# * which(tout < p2$end)
  }else{
    pout <- rep(0, length(tout))
  }
  
  results <- list(
    tout = tout,
    Iclass = Iclass,
    Isaclass = Isaclass,
    Issclass = Issclass,
    Insclass = Insclass,
    Hclass = Hclass,
    Dclass = Dclass,
    Vclass = Vclass,
    y0new = y0new,
    betamod = betamod,
    pout = pout
  )
  
  return(results)
}

################################################################################
#ODEs:

odes <- function(y, day, params) {
  ntot <- params$ntot
  
  p2 <- params$p2
  
  S <- y[1:ntot]
  E <- y[(ntot + 1):(2 * ntot)]
  Ina <- y[(2 * ntot + 1):(3 * ntot)]
  Isa <- y[(3*ntot+1) : (4*ntot) ]
  Ins <- y[(4*ntot+1) : (5*ntot)]
  Iss <- y[(5*ntot+1): (6*ntot)]
  H   <- y[(6*ntot+1): (7*ntot)]
  R  <-  y[(7*ntot+1): (8*ntot)]
  Shv1 <- y[(8*ntot+1): (9*ntot)]
  Sv1 <- y[(9*ntot+1):(10*ntot)]
  Ev1 <- y[(10*ntot+1):(11*ntot)]
  Inav1 <- y[(11*ntot+1): (12*ntot)]
  Isav1 <- y[(12*ntot+1):(13*ntot)]
  Insv1 <- y[(13*ntot+1): (14*ntot)]
  Issv1 <- y[(14*ntot+1): (15*ntot)]
  Hv1   <- y[(15*ntot+1): (16*ntot)]
  Rv1   <- y[(16*ntot+1): (17*ntot)]
  DE    <- y[(17*ntot+1): (18*ntot)]
  V     <- y[(18*ntot+1):(19*ntot)]
  Sn    <- y[(19*ntot+1):(20*ntot)]
  
  # Hospital Occupancy
  
  occ   <- max(1,sum(H+Hv1))
  Hmax  <- p2$Hmax
  SHmax <- p2$SHmax
  
  # Time-dependent disease parameters 
  
  # Amplitudes
  
  amp <- (Sn+(1-dis$heff)*(S-Sn))/S
  th0 <- max(1, (1+1.87)*((occ-Hmax)/(SHmax-Hmax)))
  
  # Probabilities
  ph <- amp*(dis$ph)
  pd <- min(th0*dis$pd,1)
  
  # Calculations
  Ts <- ((1-ph)* dis$Tsr) + (ph*(dis$Tsh))
  Th <- ((1-pd)* dis$Threc)+ (pd*(dis$Thd))
  
  sig1 <- dis$sig1
  sig2 <- dis$sig2
  g1   <- dis$g1
  g2   <- (1-ph)/Ts
  g3   <- (1-pd)/Th
  h    <- ph/Ts
  mu   <- pd/Th
  nu   <- dis$nu
  
  # Transmission
  red  <- dis$red
  beta <- dis$beta
  
  # Vaccination
  hrv1  <- dis$hrv1    
  scv1  <- dis$scv1 
  g2_v1 <- dis$g2_v1
  h_v1  <- dis$h_v1
  trv1  <- dis$trv1
  nuv1  <- dis$nuv1
  
  # Preparedness
  
  dur   <- p2$dur
  qg1   <- p2$qg1
  qg2   <- (1-ph)/(Ts-dur)
  qg2_v1 <- p2$qg2_v1
  qh     <- ph/(Ts-dur)
  qh_v1  <- p2$qh_v1
  
  startp1 <- p2$startp1
  startp2 <- p2$startp2
  startp3 <- p2$startp3
  startp4 <- p2$startp4
  pend    <- p2$end
  
  ratep1 <- p2$ratep1
  ratep2 <- p2$ratep2
  ratep3 <- p2$ratep3
  ratep4 <- p2$ratep4
  
  phi <- params$phi
  betamod <- params$betamod
  NN0 <- params$NN0
  D <- params$D
  
  # Force of Infection; phi = 1 in params; betamod = 1 in params
  
  ddk    = 10^5*sum(mu*(H+Hv1))/sum(NN0)
  
  sd_fun <- function(l, b, x) {
    (l - b) + (1 - l + b) * (1 + ((l - 1) / (1 - l + b)))^(x / 10)
  }
  
  
  I <- (red * Ina + Ins) + (1 - trv1) * (red * Inav1 + Insv1)
  foi <- phi * beta * betamod * (D %*% (I / NN0))
  
  seedvec <- rep(10^-15 * sum(data$Npop), ntot)
  seed <- phi * beta * betamod * (D %*% (seedvec / NN0))
  
  # Self-Isolation
  
  if (day < p2$t_tit) {
    p3 <- 0#rep(0, ntot)
    p4 <- 0#rep(0, ntot)
  } else if (day < p2$end && params$i != 5) {
    
    Ip  <- 10^5* sum(Ina+Ins+Isa+Iss+Inav1+Insv1+Isav1+Issv1)/sum(NN0)
    trate <- p2$trate
    #b0    = 2.197
    #b1    = 0.1838
    #b2    = -1.024
    p3  <- c(as.numeric(Ip<trate) *   (1/(1+exp(params$b0+ (params$b1*Ip) + (params$b2*log10(trate)))))/dur +
           as.numeric(Ip>=trate)*min(1 / (1+exp(params$b0+ (params$b1*Ip) + (params$b2*log10(trate)))),trate/10^5)/dur)
    p4    <- c(p3)
    
  } else {
    p3 <- 0#rep(0, ntot)
    p4 <- 0#rep(0, ntot)
  }
  
  # Vaccination
  
  nonVax = NN0 - V
  
  if (day >= pend) {
    
    v1rates <- rep(0, ntot)
    v1rater <- rep(0, ntot)
    Vdot <- rep(0, ntot)
    
  } else if (day>= startp4) {
    
    v1rates <- ratep4*S/nonVax
    v1rater <- ratep4*R/nonVax
    Vdot    <-  ratep4
    
  } else if (day >= startp3) {
    
    v1rates <- ratep3*S/nonVax
    v1rater <- ratep3*R/nonVax
    Vdot   <- ratep3
    
  } else if (day>= startp2) {
    
    v1rates <- ratep2*S/nonVax
    v1rater <- ratep2*R/nonVax
    Vdot    <-  ratep2
    
  } else if (day>=startp1) {
    
    v1rates <- ratep1*S/nonVax
    v1rater <- ratep1*R/nonVax
    Vdot    <- ratep1
    
  }  else {
    
    v1rates <- rep(0, ntot) 
    v1rater <- rep(0, ntot) 
    Vdot    <- rep(0, ntot) 
    
  }
  
  #if (day>22){
  #  browser()
  #}
  
  # Equations
  
  Sndot       <-     -Sn*(foi+seed) - ( (v1rates*Sn)/S )
  Sdot        <-     -S*(foi+seed)  + (nu*R)  - v1rates +  ( nuv1*Sv1 )
  Shv1dot     <-      v1rates  -  ( hrv1*Shv1 )  - ( Shv1*foi )
  Sv1dot      <-      ( hrv1*Shv1 ) - (Sv1*(1-scv1)*foi)  - (nuv1*Sv1)  
  Edot        <-      S*(foi+seed)  + (Shv1*foi)  - ( (sig1+sig2)*E )
  Ev1dot      <-      ( Sv1 * (1-scv1)* foi )  - ( (sig1+sig2)*Ev1 )
  Inadot      <-      ( sig1 * E )  - (g1 * Ina )   - (p3*Ina)
  Insdot      <-      ( sig2 * E )  - ( (g2+h)*Ins )  - ( p4*Ins)
  Inav1dot    <-      (sig1 * Ev1 )  - (g1*Inav1 )  - (p3*Inav1)
  Insv1dot    <-      ( sig2 * Ev1 )  - ( g2_v1 + h_v1)*Insv1 - (p4*Insv1)
  Isadot      <-      (p3*Ina )  - (qg1 * Isa)
  Issdot      <-      (p4*Ins )  - ( (qg2 + qh)*Iss )
  Isav1dot    <-      (p3*Inav1) - (qg1*Isav1)
  Issv1dot    <-      (p4*Insv1) - ( (qg2_v1+qh_v1)*Issv1 )
  Hdot        <-      (h*Ins)   + (qh*Iss)  - (g3+mu)*H
  Hv1dot      <-      (h_v1*Insv1) + (qh_v1*Issv1) - (g3+mu)*Hv1
  Rdot        <-      (g1*Ina)  + (qg1*Isa) + (g2*Ins)  + (qg2*Iss)   + (g3*H ) - (nu*R)  -v1rater
  Rv1dot      <-      (g1*Inav1) + (qg1*Isav1)  + (g2_v1 * Insv1 )  + (qg2_v1*Issv1)  + (g3*Hv1)  + v1rater  
  DEdot       <-      (mu*H )    + (mu*Hv1)
  
  f <- c(Sdot, Edot, Inadot, Isadot, Insdot, Issdot, Hdot, Rdot, Shv1dot, Sv1dot, 
         Ev1dot, Inav1dot, Isav1dot, Insv1dot, Issv1dot, Hv1dot, Rv1dot, DEdot, Vdot, Sndot)
  
  # Keeping only the positives
  f[which(y<0)] <- pmax(f[which(y<0)], 0) #xx eps
  
  # for g
  g <- h * (Ins + Iss) + h_v1 * (Insv1 + Issv1)
  
  #browser(expr = {length(f)<980})
  
  return(list(f))#, g #xx
}

################################################################################
#Make all parameters/objects:

p2params <- function(data, inp2) {
  
  data$alpha <- 1 #xx Check not defined elsewhere
  
  #Population by age:
  nn <- data$Npop
  lnn <- length(nn)
  nn <- c(nn[1:16], sum(nn[17:lnn]))
  nntot <- c(nn[1], sum(nn[2:4]), sum(nn[5:13]), sum(nn[14:length(nn)]))
  ranges <- c(1, 3, 9, 4)
  nntot <- rep.int(nntot, times=ranges)
  nnprop <- nn/nntot
  subs <- c(1:4)
  subs <- rep.int(subs, times=ranges)
  
  #Population by sector:
  adInd <- 3
  lx <- length(data$obj)
  ntot <- length(data$NNs)#Vector - ML code specifies dim=1
  data$NNs[which(data$NNs==0)] <- 1
  data$alp <- 1
  
  #Contact matrix:
  listOut <- p2MakeDs(data, data$NNs, rep(1, lx), rep(0,lx))
  Dout <- listOut$Dout
  data <- listOut$data
  
  ## INITIAL DISEASE PARAMETERS:
  
  #if (inp2=='Influenza 2009'){
    #dis <- p2Params_Flu2009
  #} elseif(inp2=='Influenza 1957'){
    #dis <-  p2Params_Flu1957
  #} elseif(inp2,'Influenza 1918'){
    #dis <-  p2Params_Flu1918
  #}elseif(inp2,'Covid Wildtype'){
    dis <-  p2Params_CovidWT()
  #}elseif(inp2,'Covid Omicron'){
    #dis <-  p2Params_CovidOM;
  #}elseif(inp2,'Covid Delta'){
    #dis <-  p2Params_CovidDE 
  #}elseif(inp2,'SARS'){
    #dis <-  p2Params_SARS
  #}else{
    #stop('Unknown Disease!')
  #}
  
  #Probabilities
  phgs    <- dis$ihr/dis$ps    #4*1
  pdgh    <- dis$ifr/dis$ihr
  phgs    <- accumarray(subs, phgs*nnprop)
  dis$ph  <- c(rep(phgs[adInd],lx), phgs)
  nnh     <- nn*dis$ihr
  nnhtot  <- c(nnh[1], sum(nnh[2:4]), sum(nnh[5:13]), sum(nnh[14:length(nnh)])) #1*17
  nnhtot  <- rep.int(nnhtot, times=ranges)
  nnhprop <- nnh/nnhtot
  pdgh    <- accumarray(subs, pdgh*nnhprop)
  dis$pd  <- c(rep(pdgh[adInd],lx), pdgh)
  
  #Durations (for each sector)
  dis$Ts = ((1-dis$ph)*dis$Tsr)   + (dis$ph*dis$Tsh)
  dis$Th = ((1-dis$pd)*dis$Threc) + (dis$pd*dis$Thd)
  
  #Rates
  dis$sig1 <- (1-dis$ps)/dis$Tlat  #0.088
  dis$sig2 <- dis$ps/dis$Tlat      # 0.1293
  dis$g1   <- 1/dis$Tay            # 0.4762
  dis$g2   <- (1-dis$ph)/dis$Ts    #[49 x 1]
  dis$g3   <- (1-dis$pd)/dis$Th    #[49 x 1]
  dis$h    <- dis$ph/dis$Ts
  dis$mu   <- dis$pd/dis$Th
  dis$nu   <- 1/dis$Ti
  
  #Transmission
  Deff  <- Dout*matrix(rep(data$NNs,ntot), ntot, ntot)/t(matrix(rep(data$NNs, ntot), ntot, ntot)) # [49 x 49]
  onesn <- rep(1, ntot)
  Fmat     <- matrix(0, 3*ntot, 3*ntot); 
  Fmat[1:ntot,(ntot+1):dim(Fmat)[2]] <- cbind(dis$red*Deff, Deff);   # [147 x 147] #xx dis$red scalar
  
  vvec <- c((dis$sig1+dis$sig2)*onesn, dis$g1*onesn, (dis$g2+dis$h)*onesn) #g2 and h are vectors
  V    <- diag(vvec)
  V[(ntot+1):(2*ntot), 1:ntot]   <- diag(-dis$sig1*onesn)
  V[(2*ntot+1):(3*ntot), 1:ntot] <- diag(-dis$sig2*onesn)
  
  GD <- Fmat%*%inv(V) # [147 x 147]
  ev <- eigen(GD,only.values = T)#largest in magnitude (+/-)  % 7.29
  d <- ev$values
  R0a <- max(Re(d)) # 7.29
  dis$beta <- dis$R0/R0a#beta scales actual R0 to fitted R0
  
  #Vaccination
  dis$hrv1 <- 1/28                       #time to develop v-acquired immunity
  dis$scv1 <- 0.60                       #infection-blocking efficacy
  dis$heff <- 0.87                       #severe-disease-blocking efficacy
  dis$hv1  <- 1-((1-dis$heff)/(1-dis$scv1))  # 0.6750 probability of reduction in infection/overall VE combining severe and symptomatic infection
  dis$trv1 <- 0.52                       #transmission-blocking efficacy %0.52
  dis$nuv1 <- 1/365                      #duration of v-acquired immunity 0.0027
  
  dis$Ts_v1 <- ((1-(1-dis$hv1)*dis$ph)*dis$Tsr)  +((1-dis$hv1)*dis$ph*dis$Tsh) # 4 days  [49x1]
  dis$g2_v1 <- (1-(1-dis$hv1)*dis$ph)/dis$Ts_v1 # [49 x 1]
  dis$h_v1  <- (1-dis$hv1)*dis$ph/dis$Ts_v1 # hospitalisation rate for vaccinated individuals [49x1]
  
  ## PREPAREDNESS PARAMETERS:
  
  p2 <- list()
  
  p2$t_tit <- data$t_tit                      #Test-Isolate-Trace Time
  p2$trate <- data$trate                      #Test-Isolate-Trace Rate
  p2$sdl   <- data$sdl                        #Social Distancing Asymptote
  p2$sdb   <- data$sdb                        #Social Distancing Steepness
  p2$Hmax  <- data$Hmax*sum(data$Npop)/10^5   #Hospital Capacity
  t_vax    <- data$t_vax                      #Vaccine Administration Time
  arate    <- data$arate*sum(data$Npop/10^5)  #Vaccine Administration Rate
  puptake  <- data$puptake                    #Vaccine Uptake
  
  #Response Time
  J                                   <- matrix(0, 7*ntot, 7*ntot)
  J[1:ntot, (2*ntot+1):(3*ntot)]          <- -dis$beta*dis$red*Dout
  J[1:ntot, (3*ntot+1):(4*ntot)]          <- -dis$beta*Dout
  J[1:ntot, (5*ntot+1):(6*ntot)]          <- diag(onesn*dis$nu)
  J[(ntot+1):(2*ntot), (1*ntot+1):(2*ntot)]   <- diag(onesn*(-dis$sig1-dis$sig2))
  J[(ntot+1):(2*ntot), (2*ntot+1):(3*ntot)]   <- dis$beta*dis$red*Dout
  J[(ntot+1):(2*ntot), (3*ntot+1):(4*ntot)]   <- dis$beta*Dout
  J[(2*ntot+1):(3*ntot), (1*ntot+1):(2*ntot)] <- diag(onesn*dis$sig1)
  J[(2*ntot+1):(3*ntot), (2*ntot+1):(3*ntot)] <- diag(onesn*-dis$g1)
  J[(3*ntot+1):(4*ntot), (1*ntot+1):(2*ntot)] <- diag(onesn*dis$sig2)
  J[(3*ntot+1):(4*ntot), (3*ntot+1):(4*ntot)] <- diag(onesn*(-dis$g2-dis$h))
  J[(4*ntot+1):(5*ntot), (3*ntot+1):(4*ntot)] <- diag(onesn*dis$h)
  J[(4*ntot+1):(5*ntot), (4*ntot+1):(5*ntot)] <- diag(onesn*(-dis$g3-dis$mu))
  J[(5*ntot+1):(6*ntot), (2*ntot+1):(3*ntot)] <- diag(onesn*dis$g1)
  J[(5*ntot+1):(6*ntot), (3*ntot+1):(4*ntot)] <- diag(onesn*dis$g2)
  J[(5*ntot+1):(6*ntot), (4*ntot+1):(5*ntot)] <- diag(onesn*dis$g3)
  J[(5*ntot+1):(6*ntot), (5*ntot+1):(6*ntot)] <- diag(onesn*-dis$nu)
  J[(6*ntot+1):(7*ntot), (4*ntot+1):(5*ntot)] <- diag(onesn*dis$mu)
  
  ev <- eigen(J)
  r       <- max(Re(ev$values))
  Td      <- log(2)/r
  if (is.null(data$Td_CWT)){
    data$Td_CWT <- Td
  }
  
  #Test-Isolate-Trace
  p2$dur    <- 1
  p2$qg1    <- 1/(dis$Tay-p2$dur)
  p2$qg2    <- (1-dis$ph)/(dis$Ts-p2$dur)
  p2$qg2_v1 <- (1-(1-dis$hv1)*dis$ph)/(dis$Ts_v1-p2$dur)
  p2$qh     <- dis$ph/(dis$Ts-p2$dur)
  p2$qh_v1  <- (1-dis$hv1)*dis$ph/(dis$Ts_v1-p2$dur)
  
  #Hospital Capacity
  p2$thl   <- max(1, 0.25*p2$Hmax)#lower threshold can't be less than 1 occupant
  p2$Hmax  <- max(4*p2$thl, p2$Hmax)
  p2$SHmax <- 2*p2$Hmax
  
  #Vaccine Uptake
  Npop    <- data$Npop
  NNage   <- c(Npop[1],sum(Npop[2:4]),sum(Npop[5:13]),sum(Npop[14:length(Npop)]))
  puptake <- min(0.99*(1-NNage[1]/sum(NNage)), puptake)#population uptake cannot be greater than full coverage in non-pre-school age groups
  up3fun  <- {function(u3) puptake*sum(NNage) - u3*(NNage[2]/2 + NNage[3]) - min(1.5*u3, 1)*NNage[4]}
  if (up3fun(0)*up3fun(1)<=0){
    u3  <- uniroot(up3fun, c(0, 1))#xx Check same
    u3 <- u3$xmin #xx Check uniroot outputs
  } else{
    u3  <- fminbnd(up3fun, 0, 1)
    u3 <- u3$xmin
  }
  u4      <- min(1.5*u3, 1)
  u1      <- 0
  up2fun  <- {function(u2) u2*NNage[2] + u3*NNage[3] + u4*NNage[4] - puptake*sum(NNage)}
  u2      <- uniroot(up2fun, c(0, 1));#xx Check same
  u2 <- u2$root
  uptake  <- c(u1,u2,u3,u4);
  
  #Vaccine Administration Rate
  t_ages     <- pmin((uptake*NNage)/c(arate), Inf)#arate may be 0 #xx Problem here
  
  if (inp2=="Influenza 1918"){
    t_ages     <- c(t_ages[3], t_ages[4], t_ages[2], t_ages[1])
    p2$aratep1 <- c(0, 0, arate, 0)#Period 1 - working-age#to be split across all economic sectors in heSimCovid19vax.m
    p2$aratep2 <- c(0, 0, 0, arate)#Period 2 - retired-age
    p2$aratep3 <- c(0, arate, 0, 0)#Period 3 - school-age
    p2$aratep4 <- c(0, 0, 0, 0)    #Period 4 - pre-school-age
  } else{
    t_ages     <- c(t_ages[4], t_ages[3], t_ages[2], t_ages[1])
    p2$aratep1 <- c(0, 0, 0, arate)#Period 1 - retired-age
    p2$aratep2 <- c(0, 0, arate, 0)#Period 2 - working-age%to be split across all economic sectors in heSimCovid19vax.m
    p2$aratep3 <- c(0, arate, 0, 0)#Period 3 - school-age
    p2$aratep4 <- c(0, 0, 0, 0)    #Period 4 - pre-school-age
  }    
  tpoints    <- cumsum(c(t_vax, t_ages))
  p2$startp1 <- tpoints[1]
  p2$startp2 <- tpoints[2]
  p2$startp3 <- tpoints[3]
  p2$startp4 <- tpoints[4]
  p2$end     <- tpoints[5]#End of Rollout
  
  ## COST PARAMETERS:
  
  na    <- c(data$Npop[1:16], sum(data$Npop[17:length(Npop)]))#length is 17 to match ifr
  la   <- c(data$la[1:16], dot(data$la[17:length(data$la)], c(data$Npop[17], sum(data$Npop[18:length(data$Npop)])))/sum(data$Npop[17:length(data$Npop)]))
  napd <- na*dis$ifr
  lg   <- c(dot(la[1], napd[1])/sum(napd[1]), 
            dot(la[2:4], napd[2:4])/sum(napd[2:4]), 
            dot(la[5:13], napd[5:13])/sum(napd[5:13]), 
            dot(la[14:length(la)], napd[14:length(napd)])/sum(napd[4:length(napd)]))
  
  lgh <- rep(0,length(lg))
  for (k in 1:length(lg)){
    lgh[k] <- sum(1/((1+0.03)^(1:lg[k])))
  }  
  data$lgh   <- c(rep(lgh[3],45), lgh)
  
  return(list(data=data, dis=dis, p2=p2))
  
}

################################################################################
#Prepare objects for simulation:
#NN <- data$NNs; x <- rep(1, lx); hw <- rep(0,lx)

p2MakeDs <- function(data, NN, x, hw) {
  C <- data$CM
  Npop <- data$Npop
  Npop[16] <- sum(Npop[16:length(Npop)])
  Npop <- Npop[1:16]
  C <- cbind(C[,1],rowSums(C[,2:4]),rowSums(C[,5:13]),rowSums(C[,14:16]))#Column sums
  C <- rbind(C[1,],
             Npop[2:4]%*%C[2:4,]/sum(Npop[2:4]),
             Npop[5:13]%*%C[5:13,]/sum(Npop[5:13]),
             Npop[14:16]%*%C[14:16,]/sum(Npop[14:16]))
  Cav <- (c(Npop[1],sum(Npop[2:4]),sum(Npop[5:13]),sum(Npop[14:16]))/sum(Npop))%*%rowSums(C)#weighted average of rows
  C <- data$comm[1,1]*(C/Cav[1,1])#xx Better way than as.numeric
  
  ##
  
  adInd <- 3#Adult index
  CworkRow <- C[adInd,]
  lx <- length(x)#Number of sectors xx rows are sectors xx vector therefore "length", not "nrow"
  ln <- length(NN)
  
  NNrep <- t(matrix(rep(NN/sum(NN),ln),ln,ln))#Total population proportion matrix
  NNrel <- NN[c(1:lx,lx+adInd)]/sum(NN[c(1:lx,lx+adInd)])#Adult proportion proportion vector
  NNrea <- t(matrix(rep(NN[1:lx]/sum(NN[1:lx]),lx),lx,lx))#Workforce population proportion matrix
  
  #Make A:
  matA <- matrix(0,ln,ln)
  matA[(lx+1):ln,(lx+1):ln] <- C
  matA[(1:lx),(lx+1):ln] <- t(matrix(rep(CworkRow,lx),ln-lx,lx))
  matA[,c(1:lx,lx+adInd)] <- matrix(rep(matA[,(lx+adInd)],lx+1),ln,lx+1)*t(matrix(rep(NNrel,ln),lx+1,ln))
  
  ##
  
  data$EdInd <- 41#Education sector index
  data$HospInd <- c(32,43,44)#Hospitality sector indices
  w <- x^(1/data$alpha)
  w[data$EdInd] <- x[data$EdInd];
  
  if (lx==45){
    #Education:
    matA[lx+1,lx+1] <- matA[lx+1,lx+1] + w[data$EdInd]^2*data$schoolA1#Mixing within age groups only
    matA[lx+2,lx+2] <- matA[lx+2,lx+2] + w[data$EdInd]^2*data$schoolA2
    
    #Hospitality:
    psub <- data$NNs[data$HospInd, 1]
    psub <- sum(psub*x[data$HospInd])/sum(psub)#Constant from 0-1, weighted measure of how much sectors are open
    matA[c(1:lx,lx+adInd),] <- matA[c(1:lx,lx+adInd),] + c(psub^2*data$hospA3)*NNrep[c(1:lx,lx+adInd),]
    matA[lx+2,] <- matA[lx+2,] + c(psub^2*data$hospA2)*NNrep[lx+2,]
    matA[ln,] <- matA[ln,] + c(psub^2*data$hospA4)*NNrep[ln,]
  } else{
    stop("Unknown economic configuration!")
  }
  
  #Transport:
  matA[1:lx,1:lx] <- 
    matA[1:lx,1:lx] + 
    t(matrix(rep(w,lx),lx,lx))*c(data$travelA3)*NNrea*t(matrix(rep(1-hw,lx),lx,lx))*matrix(rep(1-hw,lx),lx,lx)#Home working has compound effect
  
  #Worker-worker and community-worker matrices:
  
  #Make B and C
  valB <- data[["B"]]
  valB <- valB*(1-hw)*(1-hw)
  valC <- data$C
  valC <- valC*(1-hw)
  valB[(lx+1):ln] <- rep(0,ln-lx)
  valC[(lx+1):ln] <- rep(0,ln-lx)
  x[(lx+1):ln] <- rep(0,ln-lx)
  w[(lx+1):ln] <- rep(0,ln-lx)
  matB <- diag(w*valB)
  matC <- matrix(rep(x*valC,ln),ln,ln)*NNrep
  
  checkExists <- data$wnorm
  if (is.null(checkExists)){#(!exists(data$wnorm)){
    data$wnorm <- dot(rowSums(matB + matC),NN)/sum(NN[c(1:lx,lx+adInd)])
  }
  
  D <- matA + c(data$workp/data$wnorm)*(matB + matC)
  
  return(list("Dout" = D, "data" = data))
}

p2Cost <- function(data, dis, p2, g) {
  
  day <- g[, 1]
  lt <- length(day)
  lx <- length(data$obj)
  ln <- lx + 4
  
  # Initialising the variables cost and ccost_t that p2Cost returns
  
  cost <- matrix(0, nrow = 10, ncol = ln)
  ccost_t <- matrix(0, nrow = nrow(g),  ncol = 4*ln) 
  
  # VLYL
  
  deaths <-  g[ nrow(g), ( 1 + 2*lx + 4*ln + 1):(1 + 2*lx + 5*ln)]
  cost[1,] <- deaths
  
  lyl <- deaths*data$lgh

  cost[2,] <- lyl
  
  vlyl <- lyl*c(data$vly)
  cost[3,] <- vlyl
  
  deaths <- g[, (1 + 2*lx + 4*ln +1):(1 +2*lx+5*ln)]
  
  ccost_t[,1:ln] <- deaths * t(matrix(rep(data$lgh, lt), ln, lt)) * c(data$vly)
  
  # VSYL
  
  Stu <- lx + 2
  students <- data$NNs[Stu]
  cost[4, lx + 1:2] <- students
  isoasy <- g[ ,1 + 2 * lx + 0* ln+ Stu] * 14 / (dis$Tay - p2$dur)
  isosym <- g[ ,1 + 2 * lx + 1* ln+Stu]
  isorec <- g[ ,1 + 2 * lx + 1* ln+Stu]*(14-dis$Ts[Stu] + p2$dur)/(dis$Ts[Stu] - p2$dur)
  nissym <- g[ ,1 + 2 * lx + 2* ln+Stu]
  hospts <- g[ ,1 + 2 * lx + 3* ln+Stu]
  deaths <- g[ ,1 + 2 * lx + 4* ln+Stu]
  abs   <- isoasy + isosym + isorec + nissym + hospts + deaths
  absint <- trapz(day, abs)/365
  cost[5, lx + 1] <- absint
  vsyl_sts <- absint * data$vsy
  cost[6, lx + 1] <- vsyl_sts
  
  # Student Demand
  
  pres <- students - abs
  presl <- pres*(1 - g[, 1 + data$EdInd])
  preslint <- trapz(day, presl) / 365
  cost[5, lx + 2] <- preslint
  vsyl_std <- preslint * data$vsy
  cost[6, lx + 2] <- vsyl_std
  
  #ccost_t[, ln + lx + 1] <- cumtrapz(day, abs) / 365 * c(data$vsy)
  #ccost_t[, ln + lx + 2] <- cumtrapz(day, presl) / 365 * c(data$vsy)
  ccost_t <- cbind(ccost_t, (cumtrapz(day, abs) / 365 * c(data$vsy)))
  ccost_t <- cbind(ccost_t, cumtrapz(day, presl) / 365 * c(data$vsy))
  
  # SGDPL
  
  notEd <- c(1:(data$EdInd - 1), (data$EdInd + 1):lx)
  
  # Labour Supply
  
  hw <- g[, (1 + 1*lx + notEd)]
  isoasy <- g[, (1 + 2 * lx + 0* ln + notEd)] * (1 - hw) * 14 / (dis$Tay - p2$dur)  # 14-day isolation period
  isosym <- g[, (1 + 2 * lx + 0* ln + notEd)]
  isorec <- g[, (1 + 2 * lx + ln + notEd)] * (1 - hw) * (14 - dis$Ts[notEd] + p2$dur) / (dis$Ts[notEd] - p2$dur)
  nissym <- g[, (1 + 2 * lx + 2 * ln + notEd)]
  hospts <- g[, (1 + 2 * lx + 3 * ln + notEd)]
  deaths <- g[, (1 + 2 * lx + 4 * ln + notEd)] # number of workers absent
  abspc <- pmax((isoasy + isosym + isorec + nissym + hospts + deaths) / repmat(data$NNs[notEd],nrow(deaths),1), 0)  # Percentage of workers absent
  prespc <- 1 - abspc  # Percentage of workers present
  presx <- prespc^data$alp  # Percentage of GDP output
  absx <- 1 - presx  # Percentage of GDP lost
  
  absxint <- rep(0, dim(absx)[2])
  for (i in 1:dim(absx)[2]){
    absxint[i] <- trapz(day, absx[, i])
  }
  gdpl_lbs <- absxint * data$obj[notEd]
  cost[7, notEd] <- gdpl_lbs
  
  # Labour Demand
  
  w <- g[, 1+notEd]
  x <- w^data$alp
  numNotEd <- length(notEd)
  xint <- diff(day) %*% (1 - x[-1,]) #xx Check = ROW vector %*% matrix
  gdpl_lbd <- xint * data$obj[notEd]
  
  cost[8, notEd] <- gdpl_lbd
  cost[9, notEd] <- 0
  
  # Medium-term
  
  cost[10, notEd] <- 0
  
  ccost_t[, (2 * ln + notEd)] <- cumtrapz(day, absx) * t(matrix(rep(data$obj[notEd], lt), numNotEd, lt))  / lt
  ccost_t[, (3 * ln + notEd)] <- cumtrapz(day, 1 - x) / lt * data$obj[notEd]
  
  listCost <- list(cost=cost, ccost_t=ccost_t)
  return(listCost)
  
}

p2Plot <- function(data,trajectories,cost,closures){
  # variables
  nSectors <- length(data$obj)
  Hmax <- data$Hmax/1000*sum(data$NNs)
  GDP <- 365*sum(data$obj)
  edInd <- data$EdInd
  calendardays <- data$tvec
  durations <- diff(calendardays)
  nPeriods <- length(calendardays)-1
  middays <- sapply(1:nPeriods,function(x) mean(calendardays[x+0:1]))
  closuremat <- matrix(closures,ncol=nPeriods)
  ##TODO: import sector names
  sec_names <- 1:nSectors
  
  plots <- list()
  
  # costs plot
  plotcosts <- data.frame(costs=c(sum(cost[3, ]),sum(cost[7,]),sum(cost[8,]),cost[6,nSectors+1:2])/GDP,
                          detail=c('All deaths','Absences','Closures','Absences','Closures'),
                          xvals=c('Life years','GDP','GDP','Education','Education'))
  
  plots[[1]] <- ggplot(plotcosts) + 
    geom_bar(aes(x=xvals,y=costs,fill=detail),position='stack',stat='identity') +
    theme_bw(base_size=15) + 
    scale_fill_manual(values=c(`All deaths`='black',Closures='gold',Absences='hotpink')) +
    labs(x='',y='Cost, % of GDP',fill='')
  
  
  # closures plot
  closureplot <- data.frame(period=rep(middays,each=nSectors),
                   duration=rep(durations,each=nSectors),
                   sector=rep(1:nSectors,nPeriods),
                   closure=c(100*closuremat[nSectors:1,]))
  
  options(repr.plot.width = 1, repr.plot.height = 0.75)
  plots[[2]] <- ggplot(closureplot, aes(x=period, 
                               y=sector, 
                               width=duration, 
                               fill = closure)) + 
    geom_tile() +
    scale_fill_gradientn(limits=c(0,100),colours = colorRampPalette(c("black",'red',"yellow","white"))(7)) +   
    theme_bw(base_size=15) +                                 
    labs(title = "",fill='Sector \nopen, %') +
    scale_x_continuous(name='Day',breaks=calendardays,labels=round(calendardays),expand=c(0,0)) +
    theme(axis.text.x = element_text(angle = 45,  hjust=1,vjust=1)) +
    scale_y_continuous(name='',breaks=nSectors:1,labels=sec_names,expand=c(0,0)) +
    theme(
      # plot.title = element_text(vjust = -1),
      legend.position = "right", 
      legend.title = element_text(size=12,vjust=2),
      legend.text = element_text(size=10),
      # legend.spacing.x = unit(00, 'cm'),
      # legend.box.spacing = unit(0.0, 'cm'),
      axis.text.y = element_text(size=8))
  
  
  # trajectories plot
  melttraj <- reshape2::melt(trajectories,id.vars='Day')
  rectangles <- data.frame(xmin=calendardays[1:nPeriods],
                           xmax=calendardays[-1],
                           ymin=-Inf,ymax=Inf,
                           closure=1-apply(closuremat[-edInd,],2,min))
  hosp_cap <- data.frame(y=Hmax,label='Hospital capacity',variable='Hospital occupancy')
  nudgey <- ifelse(Hmax>1.5*max(trajectories$`Hospital occupancy`),-0.05*Hmax,0.1*Hmax)
  plots[[3]] <- ggplot(subset(melttraj,variable%in%c('Infections', 'Hospital occupancy', 'Deaths (cumulative)', 'Vaccine coverage'))) +
    facet_wrap(~variable,scale='free_y') + 
    theme_bw(base_size=15) + 
    geom_rect(data=rectangles,aes(xmin=xmin,xmax=xmax,ymin=ymin,ymax=ymax,alpha=I(closure)),fill='goldenrod1') +
    geom_hline(data=hosp_cap,aes(yintercept=y),colour='red3') +
    geom_text(data=hosp_cap,aes(x=median(rectangles$xmax),y=y,label=label),colour='red3',nudge_y = nudgey) +
    geom_line(aes(x=Day,y=value),linewidth=1.5) + 
    labs(y='',x='Day')
  
  for(i in 1:length(plots)) {x11(); print(plots[[i]])}
  
  return(plots)
}


