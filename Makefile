.PHONY: server data one eval report dashboard test playground clean

server:            ## start the mock address services (blocks)
	python3 server/app.py

data:              ## regenerate 1,000 labelled synthetic addresses
	python3 data/generate.py 1000 > data/addresses.csv

one:               ## run a single address through the pipeline
	baml run process_address -- --address "4013 Market St, Fairview, TN 37062"

eval:              ## run all 1,000 addresses and print the summary
	baml run run_eval

report:            ## SQL over the profile store: funnel, drop-outs, accuracy, latency
	analytics/report.sh

test:              ## offline tests only, no server needed
	baml test

playground:        ## executions, call trees, flame graphs, the pipeline visualiser
	baml playground

clean:             ## wipe the local profile store
	baml clean

dashboard:         ## build analytics/dashboard.html (charts) from the latest eval run
	python3 analytics/dashboard.py
