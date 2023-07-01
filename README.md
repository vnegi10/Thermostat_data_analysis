## Thermostat_data_analysis

In this Pluto notebook, we will visualize the daily gas usage as recorded by the
thermostat. In my case, I have a Nefit Easy thermostat (Netherlands), which sends
data to a central server at Bosch.

## Prerequisite

I am running the Nefit Easy HTTP server in a docker container as described
[here.](https://github.com/TrafeX/nefiteasy-http-server-docker)
In the Pluto notebook, we connect to this locally running HTTP server, and
make "GET" requests to fetch the relevant data. The server requires the thermostat
serial number, access key and Nefit Easy app password as input. The HTTP requests
to the server do not need to be authenticated.

## How to use?

Install Pluto.jl (if not done already) by executing the following commands in your Julia REPL:

    using Pkg
    Pkg.add("Pluto")
    using Pluto
    Pluto.run() 

Clone this repository and open **Thermostat_notebook.jl** in your Pluto browser window. That's it!
You are good to go.