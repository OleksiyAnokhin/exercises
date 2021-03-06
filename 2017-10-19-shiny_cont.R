library(shiny)
library(dplyr)
library(ggplot2)
library(forcats)

#options(shiny.reactlog=TRUE)

colors = c("red","green","blue")

shinyApp(
  ui =  fluidPage(
    titlePanel("Shiny Example - Beta-Binomial"),
    sidebarLayout(
      sidebarPanel(
        actionButton("recalc", "Recalculate"),
        numericInput("nsim","Number of simulations:", value=NA, min=1e3, max=1e6),
        h4("Data:"),
        sliderInput("n", "Number of trials (n):", 1, 100, 10),
        sliderInput("x", "Number of successes (x):", 1, 100, 5),
        
        h4("Prior:"),
        selectInput(
          "prior_type", "Choose a prior:", 
          choices=c("Beta"="beta","Beta (ABC)"="beta_abc","Truncated Normal" = "trunc_norm"), 
          selected="beta"),
        conditionalPanel(
          "input.prior_type == 'beta' | input.prior_type == 'beta_abc'",
          numericInput("alpha",HTML("&alpha;:"), value=1, min=0, max=100),
          numericInput("beta",HTML("&beta;:"), value=1, min=0, max=100)
        ),
        conditionalPanel(
          "input.prior_type == 'trunc_norm'",
          numericInput("mu",HTML("&mu;:"), value=0.5, min=-5, max=5),
          numericInput("sigma",HTML("&sigma;:"), value=0.25, min=0, max=5)
        ),
        
        h4("Plotting:"),
        checkboxInput("facet","Separate densities?", value = FALSE),
        checkboxInput("customize","Customize plot output?", value = FALSE),
        conditionalPanel(
          "input.customize == true",
          selectInput("prior","Prior color:", choices = colors, selected = colors[1]),
          selectInput("likelihood","Likelihood color:", choices = colors, selected = colors[2]),
          selectInput("posterior","Posterior color:", choices = colors, selected = colors[3])
        )
      ),
      mainPanel(
        plotOutput("dists"),
        tableOutput("summary")
      )
    )
  ),
  server = function(input, output, session)
  {
    observe({
      updateSliderInput(session, "x", max = input$n)
    })
    
    observeEvent(input$prior, {
      if (input$prior == input$likelihood)
        updateSelectInput(session, "likelihood", selected = setdiff(colors, c(input$prior, input$posterior)))
      if (input$prior == input$posterior)
        updateSelectInput(session, "posterior", selected = setdiff(colors, c(input$prior, input$likelihood)))
    })
    
    observeEvent(input$likelihood, {
      if (input$likelihood == input$prior)
        updateSelectInput(session, "prior", selected = setdiff(colors, c(input$likelihood, input$posterior)))
      if (input$likelihood == input$posterior)
        updateSelectInput(session, "posterior", selected = setdiff(colors, c(input$prior, input$likelihood)))
    })
    
    observeEvent(input$posterior, {
      if (input$posterior == input$prior)
        updateSelectInput(session, "prior", selected = setdiff(colors, c(input$posterior, input$likelihood)))
      if (input$posterior == input$likelihood)
        updateSelectInput(session, "likelihood", selected = setdiff(colors, c(input$prior, input$posterior)))
    })
    
    sims_prior = reactive({
      input$recalc
      
      req(input$nsim)
      validate(
        need(input$nsim <= 100000, "Number of sims too large, reduce to prevent shiny from locking up.")
      )
      
      if (input$prior_type == "beta" | input$prior_type == "beta_abc") {
        rbeta(input$nsim, input$alpha, input$beta)
      } else if (input$prior_type == "trunc_norm") {
        rnorm(input$nsim, input$mu, input$sigma) %>% .[. >= 0 & . <= 1]
      } else {
        stop("Unknown prior type.")
      }
    })
    
    d_prior = reactive({
      validate(
        need(length(sims_prior()) >= 1000, "Need at least 1000 simulated values from the prior. Increase number of simulations.")
      )
      
      d = density(sims_prior())
      
      data_frame(
        dist = "prior",
        p = d$x,
        d = d$y
      )
    })
    
    d_likelihood = reactive({
      data_frame(
        dist = "likelihood",
        color = input$likelihood,
        p = seq(0, 1, length.out=100)
      ) %>%
        mutate(d = dbinom(input$x, input$n, p)) %>%
        mutate(d = d / (sum(d) / n()))
    })
    
    d_posterior = reactive({
      req(input$nsim)
      validate(
        need(length(sims_prior()) >= 1000, "Need at least 1000 simulated values from the prior. Increase number of simulations.")
      )
      
      if (input$prior_type == "beta") {
        d = density( rbeta(input$nsim, input$alpha + input$x, input$beta + input$n - input$x) )
      } else {
        gen = rbinom(length(sims_prior()), size=input$n, prob=sims_prior())
        d = density(sims_prior()[gen == input$x])
      }
      
      data_frame(
        dist = "posterior",
        p = d$x,
        d = d$y
      )
    })
    
    d = reactive({
      bind_rows(
        d_prior(),
        d_likelihood(),
        d_posterior()
      ) %>%
        mutate(dist = as_factor(dist))
    })
    
    output$dists = renderPlot({
      colors = c(input$prior, input$likelihood, input$posterior)
      
      if (length(unique(colors)) != 3)
        return()
      
      g = ggplot(d(), aes(x=p, y=d, ymax=d, fill=dist)) +
        geom_ribbon(ymin=0, alpha=0.25) +
        geom_line() +
        labs(y="Density", fill="") +
        xlim(0,1) +
        scale_fill_manual(values = colors)
      
      if (input$facet)
        g = g + facet_wrap(~dist)
      
      g
    })
  }
)