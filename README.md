## Thermostat_data_analysis

In this Pluto notebook, we will visualize the daily gas usage as recorded by the
thermostat. In my case, I have a Nefit Easy thermostat (Netherlands), which sends
data to a central server at Bosch.

### Prerequisites

- #### [Docker](https://docs.docker.com/engine/install/)

- #### [Nefit Easy HTTP Server](https://github.com/TrafeX/nefiteasy-http-server-docker)
I am running the server locally in a docker container. In the Pluto notebook, we
connect to this HTTP server, and make "GET" requests to fetch the relevant data.
The server requires the thermostat serial number, access key and password (set via
Nefit Easy app) as input. The HTTP requests to the server do not need to be authenticated.

## How to use?

Install Pluto.jl (if not done already) by executing the following commands in your Julia REPL:

    using Pkg
    Pkg.add("Pluto")
    using Pluto
    Pluto.run()

Clone this repository and open **Thermostat_notebook.jl** in your Pluto browser window. That's it!
You are good to go.