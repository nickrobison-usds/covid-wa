config_file = ("config.yml")

config = covidcommon::load_config(config_file)
if(isTRUE(config$this_file_is_unedited)){
  stop(paste(
    "Please make minimal edits to the config file before running this script.
    The config file details which edits to make in it's comments."
  ))
}

simulations = config$nsimulations
scenarios = config$interventions$scenarios
deathrates = config$hospitalization$parameters$p_death_names

cat(simulations)
cat("\n")
cat(scenarios)
cat("\n")
cat(deathrates)
cat("\n")

using_importation <- FALSE
if("importation" %in% names(config)){
  using_importation <- TRUE
}

importation_target_name <- function(simulation, prefix = ""){
  paste0(".files/",prefix,simulation,"_importation")
}

importation_make_command <- function(simulation,prefix=""){
  target_name <- importation_target_name(simulation,prefix)
  dependency_name <- ""
  command_name <- paste0("$(RSCRIPT) $(PIPELINE)/R/scripts/importation.R -c  $(CONFIG)")
  touch_name <- paste0("touch ",target_name)
  return(paste0(
    target_name, ": ",
    dependency_name, "\n", 
    "\t",command_name, "\n",
    "\t",touch_name, "\n"
  ))
}

filter_target_name <- function(simulation, prefix = "" ){
  paste0(".files/",prefix,simulation,"_filter")
}

filter_make_command <- function(simulation,prefix=""){
  target_name <- filter_target_name(simulation,prefix)
  dependency_name <- importation_target_name(simulation, prefix=prefix)
  command_name<- paste0("$(RSCRIPT) $(PIPELINE)/R/scripts/create_filter.R -c $(CONFIG)")
  touch_name <- paste0("touch ",target_name)
  return(paste0(
    target_name, ": ",
    dependency_name, "\n", 
    "\t",command_name, "\n",
    "\t",touch_name, "\n"
  ))
}

hospitalizaiton_target_name <- function(simulation,scenario,deathrate, prefix = ''){
  paste0(".files/",prefix,simulation,"_hospitalization_",scenario,"_",deathrate)
}

hospitalizaiton_make_command <- function(simulation,scenario,deathrate, prefix = ''){
  target_name <- hospitalizaiton_target_name(simulation,scenario,deathrate, prefix = prefix)
  dependency_name <- simulation_target_name(simulation,scenario, prefix = prefix)
  command_name <- paste0("$(RSCRIPT) $(PIPELINE)/R/scripts/hosp_run.R -s ",scenario," -d ",deathrate, " -j $(NCOREPER)")
  touch_name <- paste0("touch ",target_name)
  return(paste0(
    target_name, ": ",
    dependency_name, "\n", 
    "\t",command_name, "\n",
    "\t",touch_name, "\n"
  ))
}

simulation_target_name <- function(simulation,scenario, prefix = ''){
  paste0(".files/", prefix,simulation,"_simulation_",scenario)
}

simulation_make_command <- function(simulation,scenario,previous_simulation, prefix = ''){
  target_name <- simulation_target_name(simulation,scenario, prefix = prefix)
  dependency_name <- ""
  if(!is.na(previous_simulation)){
    dependency_name <- simulation_target_name(previous_simulation,scenario, prefix = prefix)
  } else {
    previous_simulation <- 0
  }
  if(using_importation){
    dependency_name <- paste(dependency_name,filter_target_name(simulation,prefix),importation_target_name(simulation,prefix))
  }
  command_name <- paste0("$(PYTHON) $(PIPELINE)/simulate.py -c $(CONFIG) -s ",scenario," -n ",simulation - previous_simulation," -j $(NCOREPER)")
  touch_name <- paste0("touch ",target_name)
  return(paste0(
    target_name, ": ",
    dependency_name, "\n", 
    "\t",command_name, "\n",
    "\t",touch_name, "\n"
  ))
}

sink("Makefile")

 
cat("
.PHONY: rerun rerun_simulations rerun_hospitalization clean_hospitalization clean clean_simulations

NCOREPER=4
RSCRIPT=Rscript
PYTHON=python3
PIPELINE=COVIDScenarioPipeline/
")
cat(paste0("CONFIG=",config_file),"\n")
cat(paste0("OUTPUTBASE=",config$name),"\n")

cat("report:")
for(scenario in scenarios){
  cat(" ")
  cat(simulation_target_name(simulations,scenario))
  for(deathrate in deathrates){
    cat(" ")
    cat(hospitalizaiton_target_name(simulations,scenario,deathrate))
  }
}
cat("\n\tRscript compile_Rmd.R\n")

if(using_importation){
  for(sim_idx in seq_len(length(simulations))){
    
    cat(filter_make_command(simulations[sim_idx]))
    cat(importation_make_command(simulations[sim_idx]))
  }
}

for(sim_idx in seq_len(length(simulations))){
  sim <- simulations[sim_idx]
  prev_sim <- dplyr::lag(simulations)[sim_idx]
  for(scenario in scenarios){
    cat(simulation_make_command(sim,scenario,prev_sim))
    for(deathrate in deathrates){
      cat(hospitalizaiton_make_command(sim,scenario,deathrate))
    }
  }
}

cat(paste0("

rerun: rerun_simulations rerun_hospitalization"
))

if(using_importation){
  cat(paste0("rerun_importation rerun_filter
clean_filter: rerun_filter
\trm -rf ",config$dynfilter_path,"
clean_importation: rerun_importation
\trm -rf importation
"))
}
cat(paste0("
rerun_filter:
\trm -f .files/1*_filter
rerun_importation:
\trm -f .files/1*_importation
rerun_simulations: clean_simulations
\trm -f .files/1*_simulation*
rerun_hospitalization:
\trm -f .files/1*_hospitalization*
clean: clean_simulations clean_hospitalization clean_reports"
))
if(using_importation){
  cat(" clean_importation clean_filter")
}
cat(paste0("
clean_reports:
\trm -f notebooks/*.html
clean_simulations: rerun_simulations
\trm -rf model_output
clean_hospitalization: rerun_hospitalization
\trm -rf hospitalization
"))

sink(NULL)
