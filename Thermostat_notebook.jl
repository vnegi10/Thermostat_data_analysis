### A Pluto.jl notebook ###
# v0.19.26

using Markdown
using InteractiveUtils

# ╔═╡ ede5bca4-183b-11ee-20c6-db7b4b6ebe30
using HTTP, JSON, DataFrames, Statistics, Dates, VegaLite, Flux, LinearAlgebra

# ╔═╡ 4a8964c9-8c07-4e1c-a635-24dcd62436e3
md"
## Load packages
"

# ╔═╡ 7629b1e1-061b-4f39-ab0b-5d45b1c417e6
md"
## Make request
"

# ╔═╡ c019c571-284e-4296-8b45-1ee7355a4471
const URL = "http://127.0.0.1:3000/bridge"

# ╔═╡ f3f5a8f4-a9cf-4103-a013-7c37158a34a1
begin
	const GAS_YTD = "/ecus/rrc/recordings/yearTotal"
	const GAS_POINTER = "/ecus/rrc/recordings/gasusagePointer"	
end

# ╔═╡ 477de20d-938a-43ed-a8be-c54703146d04
gas_usage_ep(page_num) = "/ecus/rrc/recordings/gasusage?page=$(page_num)"

# ╔═╡ 6bbf347d-0e6d-4993-aee5-59673b4f1ba6
function get_request(endpoint_name::String)

    url = URL
    headers = ["Content-Type" => "application/json"]

    response = HTTP.request(
	                        "GET",
	                        join([URL, endpoint_name]),
		                    headers,
	                        verbose = 0,
	                        retries = 2
	                        )

    response_dict = String(response.body) |> JSON.parse

    return response_dict
end

# ╔═╡ c52825e6-d1e8-45a2-8502-5334264101ec
md"
#### Gas YTD
"

# ╔═╡ b0f80e35-cc97-4c4c-81f4-c622d5c4fcd5
gas_ytd_dict = get_request(GAS_YTD)

# ╔═╡ 6716974c-7ebe-49bd-9df5-698b1af168b5
md"
#### Historical gas usage
"

# ╔═╡ cac68ab1-b490-4233-ba2c-aecb4b899cd2
"""
    get_hist_gas_usage()

Fetch the historical gas usage from Nefit Easy HTTP server.
"""
function get_hist_gas_usage()

	gas_pointer_dict = get_request(GAS_POINTER)
	page_end = (gas_pointer_dict["value"] / 32) |> ceil |> Int

	all_gas = DataFrame[]

	for page = 1:page_end
		gas_usage_dict = get_request(gas_usage_ep(page))
		df_gas = vcat(DataFrame.(gas_usage_dict["value"])...)
		push!(all_gas, df_gas)
	end

	df_all_gas = vcat(all_gas...)

	return filter(row -> row.d != "255-256-65535", df_all_gas)

end

# ╔═╡ 278ac348-2c3f-4471-98cf-b7c3842b55ba
df_all_gas = get_hist_gas_usage()

# ╔═╡ 369d34ad-946a-4cc2-9e2c-74f240334845
"""
    process_gas_df(df_all_gas::DataFrame)

Add proper column names and rescale data to proper units.
"""
function process_gas_df(df_all_gas::DataFrame)

	df_gas = deepcopy(df_all_gas)

	# Temperature is 10x in original data
	df_gas[!, :T] = df_gas[!, :T] ./ 10

	# Convert from kWh to m^3
	conversion_factor = 0.10058
	df_gas[!, :ch] = df_gas[!, :ch] .* conversion_factor
	df_gas[!, :hw] = df_gas[!, :hw] .* conversion_factor

	# Convert to Date object
	df_gas[!, :d] = Date.(df_gas[!, :d], "dd-mm-yyyy")

	# Rename all colums
	rename!(df_gas, Dict(:T  => "OutsideTemperature", 
	                     :ch => "CentralHeating",
		                 :hw => "HotWater",		
	                     :d  => "Date"))

	# Get column with day names
	day = map(x -> Dates.dayname(x), df_gas[!, :Date])
	insertcols!(df_gas, ncol(df_gas), :Day => day)

	return df_gas

end

# ╔═╡ 444b047c-ec47-42ae-9b06-bd35fedb092f
md"
#### Conversion between kWh and m^3 for gas usage
CV --> Calorific Value

(gas_usage * CV * 1.02264) / 3.6 = kWh

**gas_usage = (kWh * 3.6) / (CV * 1.02264)**

1 kWh = 3.6 MJ

CV = 35 MJ/m^3 for NL [link](https://github.com/robertklep/nefit-easy-core/wiki/List-of-endpoints)

1 kWh = 0.10058 m^3 of gas
"

# ╔═╡ 160910d5-a6be-42ba-b666-62fb89bb9f00
3.6 / (35 * 1.02264)

# ╔═╡ 211c8e12-1793-4744-96ed-149cb18d91f8
df_gas = process_gas_df(df_all_gas)

# ╔═╡ 989db75a-f130-4753-8409-7c5c04a46453
md"
## Plot data
"

# ╔═╡ b8db2df8-7c91-4bcd-9f28-d84645f24d08
"""
    plot_daily_gas_usage(df_all_gas::DataFrame,
                         month::String,
                         year::Int64)

Plot the daily gas usage breakdown for a given month and year.
"""
function plot_daily_gas_usage(df_all_gas::DataFrame,
                              month::String,
                              year::Int64)

	df_gas = process_gas_df(df_all_gas)

	df_gas = filter(row -> occursin(month, Dates.monthname(row.Date)) &&
	                       Dates.year(row.Date) == year,
		                   df_gas)

	total_gas = sum(df_gas.CentralHeating) + sum(df_gas.HotWater)
	total_gas = round(total_gas, digits = 2)

	sdf_gas = stack(df_gas, 
		            [:CentralHeating, :HotWater], 
	                variable_name = :UsageType,
	                value_name = :UsageUnits)	

    figure = sdf_gas |>
	     @vlplot(:bar,
	     x = {:Date, 
			  "axis" = {"title" = "Time",
		      "labelFontSize" = 10, 
			  "titleFontSize" = 12,
			  }},
	     y = {:UsageUnits, 
		      "axis" = {"title" = "Gas usage [m^3]",
		      "labelFontSize" = 10, 
			  "titleFontSize" = 12 }},
	     width = 500, 
	     height = 300,
	    "title" = {"text" = "Daily gas usage from $month - $year, total = $total_gas m^3", 
		           "fontSize" = 14},
		 color = :UsageType)

    return figure
end

# ╔═╡ 801c3a8f-7af8-42b6-b347-a732b81c7ac6
plot_daily_gas_usage(df_all_gas, "Jan", 2023)

# ╔═╡ 1334dbf9-1496-4da8-865b-a0c9c1bbebab
"""
    plot_daily_gas_dist(df_all_gas::DataFrame,
                        month::String,
                        year::Int64)

Plot the daily gas usage distribution for a given month and year.
"""
function plot_daily_gas_dist(df_all_gas::DataFrame,
                             month::String,
                             year::Int64)

	df_gas = process_gas_df(df_all_gas)

	df_gas = filter(row -> occursin(month, Dates.monthname(row.Date)) &&
	                       Dates.year(row.Date) == year,
		                   df_gas)

	total_gas = sum(df_gas.CentralHeating) + sum(df_gas.HotWater)
	total_gas = round(total_gas, digits = 2)

	figure = df_gas |>
	     @vlplot(repeat = {column = [:CentralHeating, :HotWater]}) +		 
	     @vlplot(:bar,
	     x = {field = {repeat = :column}, 
			  "axis" = {"labelFontSize" = 10, 
			            "titleFontSize" = 12},
			  "bin" = {"maxbins" = 25}},
	     y = {"count()", 
		      "axis" = {"title" = "Number of counts",
		      "labelFontSize" = 10, 
			  "titleFontSize" = 12 }},
	     width = 400, 
	     height = 200,
	    "title" = {"text" = "Gas usage distribution from $month - $year, total = $total_gas m^3", 
		           "fontSize" = 14},
		 color = :Day)

    return figure
end

# ╔═╡ 4f4f2169-0683-4ec7-8998-c58b1f793642
plot_daily_gas_dist(df_all_gas, "Jan", 2023)

# ╔═╡ 3ae52bbe-4de4-4fda-8595-e23e766640db
plot_daily_gas_dist(df_all_gas, "Feb", 2023)

# ╔═╡ 412d51ce-79dd-4b67-9617-bfed6b2f304f
"""
    plot_daily_gas_temp(df_all_gas::DataFrame,
                  month::String,
                  year::Int64)

Plot the daily gas usage vs outside temperature for a given month and year.
"""
function plot_daily_gas_temp(df_all_gas::DataFrame,
                             month::String,
                             year::Int64)

	df_gas = process_gas_df(df_all_gas)

	df_gas = filter(row -> occursin(month, Dates.monthname(row.Date)) &&
	                       Dates.year(row.Date) == year,
		                   df_gas)

	total_gas = sum(df_gas.CentralHeating) + sum(df_gas.HotWater)
	total_gas = round(total_gas, digits = 2)	

	sdf_gas = stack(df_gas, 
		            [:CentralHeating, :OutsideTemperature], 
	                variable_name = :ColumnNames,
	                value_name = :Values)	

    figure = sdf_gas |>
	     @vlplot(mark={
                 :line,
                 point = {filled = false, fill = :white}},
	     x = {:Date, 
			  "axis" = {"title" = "Time",
		      "labelFontSize" = 10, 
			  "titleFontSize" = 12,
			  }},
	     y = {:Values, 
		      "axis" = {"title" = "Gas usage [m^3] vs Outside temp. [°C]",
		      "labelFontSize" = 10, 
			  "titleFontSize" = 12,
			  }},
	     width = 500, 
	     height = 300,
	    "title" = {"text" = " Temp. vs gas for $month - $year, total = $total_gas m^3", 
		           "fontSize" = 14},
		 color = :ColumnNames)	    

    return figure
end

# ╔═╡ be94bf72-6c4e-45d6-9428-b25c46455821
plot_daily_gas_temp(df_all_gas, "Jan", 2023)

# ╔═╡ ff4870dc-a50e-4aae-97e1-9cfbad1741d7
"""
    plot_scatter_gas_temp(df_all_gas::DataFrame)

Create a scatter plot of all the gas and temperature data.    
"""
function plot_scatter_gas_temp(df_all_gas::DataFrame)

	df_gas = process_gas_df(df_all_gas)

	total_gas = sum(df_gas.CentralHeating) + sum(df_gas.HotWater)
	total_gas = round(total_gas, digits = 2)	

	figure = df_gas |>
	     @vlplot(:point,
	     x = {:OutsideTemperature, 
			  "axis" = {"title" = "Outside temp. [°C]",
		      "labelFontSize" = 10, 
			  "titleFontSize" = 12,
			  }},
	     y = {:CentralHeating, 
		      "axis" = {"title" = "Gas usage [m^3]",
		      "labelFontSize" = 10, 
			  "titleFontSize" = 12,
			  }},
	     width = 600, 
	     height = 300,
	    "title" = {"text" = "Temp. vs gas usage, total = $total_gas m^3", 
		           "fontSize" = 14},
	     )	    

    return figure
end

# ╔═╡ f15879db-cda5-4591-a2d8-33b09b5e6c75
plot_scatter_gas_temp(df_all_gas)

# ╔═╡ fc47a9b3-87a8-464c-91de-9a33969cab99
function calculate_mahalanobis_dist(df_gas::DataFrame)

	A = [df_gas[!, :OutsideTemperature] df_gas[!, :CentralHeating]]

	A_mu = A .- mean(A)
	Q = cov(A, corrected = true)

	M_dist = A_mu * inv(Q) * A_mu'

	return diag(M_dist)	

end

# ╔═╡ b1d355f6-e86a-4e1b-9527-135432dd3fc9
#calculate_mahalanobis_dist(df_gas)

# ╔═╡ 485ab7a7-97cc-4b6d-bae2-830bcc0f65e2
"""
    plot_maha_gas_temp(df_all_gas::DataFrame)

Create a scatter plot with Mahalanobis distance of gas and temperature data.    
"""
function plot_maha_gas_temp(df_all_gas::DataFrame)

	df_gas = process_gas_df(df_all_gas)

	maha_dist = calculate_mahalanobis_dist(df_gas)
	insertcols!(df_gas, ncol(df_gas) + 1, :MahaDist => maha_dist)

	total_gas = sum(df_gas.CentralHeating) + sum(df_gas.HotWater)
	total_gas = round(total_gas, digits = 2)	

	figure = df_gas |>
	     @vlplot(:point,
	     x = {:OutsideTemperature, 
			  "axis" = {"title" = "Outside temp. [°C]",
		      "labelFontSize" = 10, 
			  "titleFontSize" = 12,
			  }},
	     y = {:CentralHeating, 
		      "axis" = {"title" = "Gas usage [m^3]",
		      "labelFontSize" = 10, 
			  "titleFontSize" = 12,
			  }},
	     width = 600, 
	     height = 300,
	    "title" = {"text" = "Temp. vs gas usage, total = $total_gas m^3", 
		           "fontSize" = 14},
	    color = {:MahaDist, "scale" = {"domainMid" = 20}}
		)	    

    return figure
end

# ╔═╡ 46fee057-ac27-4e19-9ed0-e592b63bd278
plot_maha_gas_temp(df_all_gas)

# ╔═╡ ddbb2e17-4b4d-4386-a690-eb5f2ea7bad8
md"
## Linear regression ML model

$model(W, b, x) = Wx + b$
"

# ╔═╡ 14f6bdb6-dd4e-4fb6-917e-a7e5fb9e25b9
df_gas_in = filter(row -> row.OutsideTemperature < 18, df_gas);

# ╔═╡ 8b358d53-a3c0-4f49-9544-80635627d331
x_in = Float32.(hcat(df_gas_in[!, :OutsideTemperature]...))

# ╔═╡ 887cc9c8-cfe0-46cb-aa1b-efc0cd041bb9
y_in = Float32.(hcat(df_gas_in[!, :CentralHeating]...))

# ╔═╡ 7b31217f-1170-496a-a43f-93e26bfc0fa2
md"
#### Loss function
"

# ╔═╡ f7d37dce-1e6d-4753-ba67-a7849d1e6a36
function get_loss(flux_model, x_in, y_in)

	y_model = flux_model(x_in)
    mse_error = Flux.mse(y_model, y_in)

	return mse_error
end

# ╔═╡ aeef3e40-f119-4806-a1d7-89245277ad18
flux_model = Dense(1 => 1)	

# ╔═╡ a9ee941a-d8d8-4052-8f5a-5ea6710a5ba8
get_loss(flux_model, x_in, y_in)

# ╔═╡ 7ba30f29-37dc-4e91-8c19-67d8c481d9b2
md"
#### Training function

$W --> Weights, b --> Biases$

$W = W - η* \frac{dL}{dW}$

$b = b - η* \frac{dL}{db}$
"

# ╔═╡ 8dea8490-cb8e-41cb-b71f-7d72a2c2b807
"""
    update_model!(learn, 
	              flux_model,
	              x_in, 
	              y_in)

Update weights and biases of the model using gradient descent.
"""
function update_model!(learn, 
	                   flux_model,
	                   x_in, 
	                   y_in)

	dLdm, _, _ = gradient(get_loss, flux_model, x_in, y_in)
    @. flux_model.weight = flux_model.weight - Float32(learn * dLdm.weight)
    @. flux_model.bias   = flux_model.bias - Float32(learn * dLdm.bias)

	return flux_model
	
end

# ╔═╡ 9e830453-e885-44b5-bb59-cf3592606c5f
md"
#### Run epochs
"

# ╔═╡ fb0af0bc-bbb0-44e5-b157-e5d9fc4b37bb
"""
    run_training(loss_change,
                 learn, 
	             x_in, 
	             y_in)

Run training epochs until the Δloss ≤ loss_change.
"""
function run_training(loss_change,
                      learn, 
	                  x_in, 
	                  y_in)

	# Initialize Flux model
	flux_model = Dense(1 => 1)	

	loss_initial = get_loss(flux_model, x_in, y_in)
	all_losses = [loss_initial]
	flux_model_new = nothing
	num_epochs = 0
	
	while true
		
		flux_model_new = update_model!(learn, flux_model, x_in, y_in)
		loss_new = get_loss(flux_model_new, x_in, y_in)

		num_epochs += 1
		push!(all_losses, loss_new)
		
		if abs(loss_new - loss_initial) ≤ loss_change
			break
		else
			loss_initial = loss_new
			flux_model = flux_model_new
		end

	end

	return flux_model_new, all_losses, num_epochs	

end

# ╔═╡ 4cc38a5f-8779-43c1-b229-985f04f37000
flux_model_trained, all_losses, num_epochs = run_training(0.01, 0.001, x_in, y_in)

# ╔═╡ 0a7d66d1-b7ee-4230-9d36-80d9b880c064
md"
#### Plot loss
"

# ╔═╡ 75cca775-e06e-4f76-924f-319e0b1b2303
"""
    plot_training_loss(loss_change,
                       learn, 
	                   x_in, 
	                   y_in)

Plot change in training loss w.r.t. number of epochs.
"""
function plot_training_loss(loss_change,
                            learn, 
	                        x_in, 
	                        y_in)

	_, all_losses, num_epochs = run_training(loss_change, learn, x_in, y_in)

	figure = 
	     @vlplot(mark={
                 :line,
                 point = {filled = false, fill = :white}},
	     x = {0:num_epochs, 
			  "axis" = {"title" = "Epochs",
		      "labelFontSize" = 10, 
			  "titleFontSize" = 12,
			  }},
	     y = {all_losses[1:end], 
		      "axis" = {"title" = "Calculated loss",
		      "labelFontSize" = 10, 
			  "titleFontSize" = 12,
			  }},
	     width = 500, 
	     height = 300,
	    "title" = {"text" = "Training loss vs number of epochs, total = $(num_epochs)", 
		           "fontSize" = 14},
		        )	    

    return figure
end

# ╔═╡ 6430852c-1913-47d2-9aea-b23fd489b970
@time plot_training_loss(1e-5, 0.001, x_in, y_in)

# ╔═╡ ac33ad3f-5017-4e4f-8cf8-e471aeea418d
md"
#### Plot linear fit
"

# ╔═╡ 9528f8c4-6182-4e4c-a7b3-31f826a328d2
"""
    plot_fit_gas_temp(loss_change,
                      learn, 
                      x_in, 
                      y_in)

Create a scatter plot and linear fit of all the gas and temperature data.    
"""
function plot_fit_gas_temp(loss_change,
                           learn, 
                           x_in, 
                           y_in)

	flux_model_trained, _, num_epochs = run_training(loss_change,
		                                             learn, 
		                                             x_in,
		                                             y_in)

	df_plot = DataFrame(
		                :OutsideTemp => Base.vect(x_in...),
	                    :CentralHeating => Base.vect(y_in...),
	                    :ModelFit => Base.vect(flux_model_trained(x_in)...)
	                   )

	figure = df_plot |>
		 @vlplot() +
		 
	     @vlplot(:point,
	     x = {:OutsideTemp,
			  "axis" = {"title" = "Outside temp. [°C]",
		      "labelFontSize" = 10, 
			  "titleFontSize" = 12,
			  }},
	     y = {:CentralHeating, 
		      "axis" = {"title" = "Gas usage [m^3]",
		      "labelFontSize" = 10, 
			  "titleFontSize" = 12,
			  }},
	     width = 600, 
	     height = 300,
	    "title" = {"text" = "Temp. vs gas usage, num_epochs = $(num_epochs)", 
		           "fontSize" = 14},
	     ) +
	
	     @vlplot(mark={:line, point = {filled = true, 
		                               fill = :green, 
									   shape = :square}},
	     x = {:OutsideTemp,
			  "axis" = {"title" = "Outside temp. [°C]",
		      "labelFontSize" = 10, 
			  "titleFontSize" = 12,
			  }},
	     y = {:ModelFit, 
		      "axis" = {"title" = "Gas usage [m^3]",
		      "labelFontSize" = 10, 
			  "titleFontSize" = 12,
			  }},
	     width = 600, 
	     height = 300,
	    "title" = {"text" = "Temp. vs gas usage, num_epochs = $(num_epochs)", 
		           "fontSize" = 14},
	     )

    return figure
end

# ╔═╡ df6d904a-6126-40cf-932c-f8080477cbaf
plot_fit_gas_temp(1e-5, 0.001, x_in, y_in)

# ╔═╡ f6d6640c-104b-4d83-a9cc-a67cf279c8bc


# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
Dates = "ade2ca70-3891-5945-98fb-dc099432e06a"
Flux = "587475ba-b771-5e3f-ad9e-33799f191a9c"
HTTP = "cd3eb016-35fb-5094-929b-558a96fad6f3"
JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
VegaLite = "112f6efa-9a02-5b7d-90c0-432ed331239a"

[compat]
DataFrames = "~1.5.0"
Flux = "~0.13.17"
HTTP = "~1.9.6"
JSON = "~0.21.4"
VegaLite = "~3.2.2"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.9.0"
manifest_format = "2.0"
project_hash = "c06d2c3b569bed6eec6bd77a4a373b2f59b0fb01"

[[deps.AbstractFFTs]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "8bc0aaec0ca548eb6cf5f0d7d16351650c1ee956"
uuid = "621f4979-c628-5d54-868e-fcf4e3e8185c"
version = "1.3.2"
weakdeps = ["ChainRulesCore"]

    [deps.AbstractFFTs.extensions]
    AbstractFFTsChainRulesCoreExt = "ChainRulesCore"

[[deps.Adapt]]
deps = ["LinearAlgebra", "Requires"]
git-tree-sha1 = "76289dc51920fdc6e0013c872ba9551d54961c24"
uuid = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
version = "3.6.2"
weakdeps = ["StaticArrays"]

    [deps.Adapt.extensions]
    AdaptStaticArraysExt = "StaticArrays"

[[deps.ArgCheck]]
git-tree-sha1 = "a3a402a35a2f7e0b87828ccabbd5ebfbebe356b4"
uuid = "dce04be8-c92d-5529-be00-80e4d2c0e197"
version = "2.3.0"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.1"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.Atomix]]
deps = ["UnsafeAtomics"]
git-tree-sha1 = "c06a868224ecba914baa6942988e2f2aade419be"
uuid = "a9b6321e-bd34-4604-b9c9-b65b8de01458"
version = "0.1.0"

[[deps.BFloat16s]]
deps = ["LinearAlgebra", "Printf", "Random", "Test"]
git-tree-sha1 = "dbf84058d0a8cbbadee18d25cf606934b22d7c66"
uuid = "ab4f0b2a-ad5b-11e8-123f-65d77653426b"
version = "0.4.2"

[[deps.BangBang]]
deps = ["Compat", "ConstructionBase", "InitialValues", "LinearAlgebra", "Requires", "Setfield", "Tables"]
git-tree-sha1 = "e28912ce94077686443433c2800104b061a827ed"
uuid = "198e06fe-97b7-11e9-32a5-e1d131e6ad66"
version = "0.3.39"

    [deps.BangBang.extensions]
    BangBangChainRulesCoreExt = "ChainRulesCore"
    BangBangDataFramesExt = "DataFrames"
    BangBangStaticArraysExt = "StaticArrays"
    BangBangStructArraysExt = "StructArrays"
    BangBangTypedTablesExt = "TypedTables"

    [deps.BangBang.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"
    StructArrays = "09ab397b-f2b6-538f-b94a-2f83cf4a842a"
    TypedTables = "9d95f2ec-7b3d-5a63-8d20-e2491e220bb9"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.Baselet]]
git-tree-sha1 = "aebf55e6d7795e02ca500a689d326ac979aaf89e"
uuid = "9718e550-a3fa-408a-8086-8db961cd8217"
version = "0.1.1"

[[deps.BitFlags]]
git-tree-sha1 = "43b1a4a8f797c1cddadf60499a8a077d4af2cd2d"
uuid = "d1d4a3ce-64b1-5f1a-9ba4-7e7e69966f35"
version = "0.1.7"

[[deps.BufferedStreams]]
git-tree-sha1 = "5bcb75a2979e40b29eb250cb26daab67aa8f97f5"
uuid = "e1450e63-4bb3-523b-b2a4-4ffa8c0fd77d"
version = "1.2.0"

[[deps.CEnum]]
git-tree-sha1 = "eb4cb44a499229b3b8426dcfb5dd85333951ff90"
uuid = "fa961155-64e5-5f13-b03f-caf6b980ea82"
version = "0.4.2"

[[deps.CUDA]]
deps = ["AbstractFFTs", "Adapt", "BFloat16s", "CEnum", "CUDA_Driver_jll", "CUDA_Runtime_Discovery", "CUDA_Runtime_jll", "ExprTools", "GPUArrays", "GPUCompiler", "KernelAbstractions", "LLVM", "LazyArtifacts", "Libdl", "LinearAlgebra", "Logging", "Preferences", "Printf", "Random", "Random123", "RandomNumbers", "Reexport", "Requires", "SparseArrays", "SpecialFunctions", "UnsafeAtomicsLLVM"]
git-tree-sha1 = "35160ef0f03b14768abfd68b830f8e3940e8e0dc"
uuid = "052768ef-5323-5732-b1bb-66c8b64840ba"
version = "4.4.0"

[[deps.CUDA_Driver_jll]]
deps = ["Artifacts", "JLLWrappers", "LazyArtifacts", "Libdl", "Pkg"]
git-tree-sha1 = "498f45593f6ddc0adff64a9310bb6710e851781b"
uuid = "4ee394cb-3365-5eb0-8335-949819d2adfc"
version = "0.5.0+1"

[[deps.CUDA_Runtime_Discovery]]
deps = ["Libdl"]
git-tree-sha1 = "bcc4a23cbbd99c8535a5318455dcf0f2546ec536"
uuid = "1af6417a-86b4-443c-805f-a4643ffb695f"
version = "0.2.2"

[[deps.CUDA_Runtime_jll]]
deps = ["Artifacts", "CUDA_Driver_jll", "JLLWrappers", "LazyArtifacts", "Libdl", "TOML"]
git-tree-sha1 = "5248d9c45712e51e27ba9b30eebec65658c6ce29"
uuid = "76a88914-d11a-5bdc-97e0-2f5a05c973a2"
version = "0.6.0+0"

[[deps.CUDNN_jll]]
deps = ["Artifacts", "CUDA_Runtime_jll", "JLLWrappers", "LazyArtifacts", "Libdl", "TOML"]
git-tree-sha1 = "c30b29597102341a1ea4c2175c4acae9ae522c9d"
uuid = "62b44479-cb7b-5706-934f-f13b2eb2e645"
version = "8.9.2+0"

[[deps.ChainRules]]
deps = ["Adapt", "ChainRulesCore", "Compat", "Distributed", "GPUArraysCore", "IrrationalConstants", "LinearAlgebra", "Random", "RealDot", "SparseArrays", "Statistics", "StructArrays"]
git-tree-sha1 = "1cdf290d4feec68824bfb84f4bfc9f3aba185647"
uuid = "082447d4-558c-5d27-93f4-14fc19e9eca2"
version = "1.51.1"

[[deps.ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "e30f2f4e20f7f186dc36529910beaedc60cfa644"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.16.0"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "9c209fb7536406834aa938fb149964b985de6c83"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.1"

[[deps.CommonSubexpressions]]
deps = ["MacroTools", "Test"]
git-tree-sha1 = "7b8a93dba8af7e3b42fecabf646260105ac373f7"
uuid = "bbf7d656-a473-5ed7-a52c-81e309532950"
version = "0.3.0"

[[deps.Compat]]
deps = ["UUIDs"]
git-tree-sha1 = "7a60c856b9fa189eb34f5f8a6f6b5529b7942957"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.6.1"
weakdeps = ["Dates", "LinearAlgebra"]

    [deps.Compat.extensions]
    CompatLinearAlgebraExt = "LinearAlgebra"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.0.2+0"

[[deps.CompositionsBase]]
git-tree-sha1 = "802bb88cd69dfd1509f6670416bd4434015693ad"
uuid = "a33af91c-f02d-484b-be07-31d278c5ca2b"
version = "0.1.2"

    [deps.CompositionsBase.extensions]
    CompositionsBaseInverseFunctionsExt = "InverseFunctions"

    [deps.CompositionsBase.weakdeps]
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.ConcurrentUtilities]]
deps = ["Serialization", "Sockets"]
git-tree-sha1 = "96d823b94ba8d187a6d8f0826e731195a74b90e9"
uuid = "f0e56b4a-5159-44fe-b623-3e5288b988bb"
version = "2.2.0"

[[deps.ConstructionBase]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "738fec4d684a9a6ee9598a8bfee305b26831f28c"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.5.2"

    [deps.ConstructionBase.extensions]
    ConstructionBaseIntervalSetsExt = "IntervalSets"
    ConstructionBaseStaticArraysExt = "StaticArrays"

    [deps.ConstructionBase.weakdeps]
    IntervalSets = "8197267c-284f-5f27-9208-e0e47529a953"
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"

[[deps.ContextVariablesX]]
deps = ["Compat", "Logging", "UUIDs"]
git-tree-sha1 = "25cc3803f1030ab855e383129dcd3dc294e322cc"
uuid = "6add18c4-b38d-439d-96f6-d6bc489c04c5"
version = "0.1.3"

[[deps.Crayons]]
git-tree-sha1 = "249fe38abf76d48563e2f4556bebd215aa317e15"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.1.1"

[[deps.DataAPI]]
git-tree-sha1 = "8da84edb865b0b5b0100c0666a9bc9a0b71c553c"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.15.0"

[[deps.DataFrames]]
deps = ["Compat", "DataAPI", "Future", "InlineStrings", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrettyTables", "Printf", "REPL", "Random", "Reexport", "SentinelArrays", "SnoopPrecompile", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "aa51303df86f8626a962fccb878430cdb0a97eee"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.5.0"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "d1fff3a548102f48987a52a2e0d114fa97d730f0"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.13"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.DataValues]]
deps = ["DataValueInterfaces", "Dates"]
git-tree-sha1 = "d88a19299eba280a6d062e135a43f00323ae70bf"
uuid = "e7dc6d0d-1eca-5fa6-8ad6-5aecde8b7ea5"
version = "0.4.13"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DefineSingletons]]
git-tree-sha1 = "0fba8b706d0178b4dc7fd44a96a92382c9065c2c"
uuid = "244e2a9f-e319-4986-a169-4d1fe445cd52"
version = "0.1.2"

[[deps.DelimitedFiles]]
deps = ["Mmap"]
git-tree-sha1 = "9e2f36d3c96a820c678f2f1f1782582fcf685bae"
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"
version = "1.9.1"

[[deps.DiffResults]]
deps = ["StaticArraysCore"]
git-tree-sha1 = "782dd5f4561f5d267313f23853baaaa4c52ea621"
uuid = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
version = "1.1.0"

[[deps.DiffRules]]
deps = ["IrrationalConstants", "LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "23163d55f885173722d1e4cf0f6110cdbaf7e272"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.15.1"

[[deps.Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[deps.DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "2fb1e02f2b635d0845df5d7c167fec4dd739b00d"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.3"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[deps.ExprTools]]
git-tree-sha1 = "c1d06d129da9f55715c6c212866f5b1bddc5fa00"
uuid = "e2ba6199-217a-4e67-a87a-7c52f15ade04"
version = "0.1.9"

[[deps.FLoops]]
deps = ["BangBang", "Compat", "FLoopsBase", "InitialValues", "JuliaVariables", "MLStyle", "Serialization", "Setfield", "Transducers"]
git-tree-sha1 = "ffb97765602e3cbe59a0589d237bf07f245a8576"
uuid = "cc61a311-1640-44b5-9fba-1b764f453329"
version = "0.2.1"

[[deps.FLoopsBase]]
deps = ["ContextVariablesX"]
git-tree-sha1 = "656f7a6859be8673bf1f35da5670246b923964f7"
uuid = "b9860ae5-e623-471e-878b-f6a53c775ea6"
version = "0.1.1"

[[deps.FileIO]]
deps = ["Pkg", "Requires", "UUIDs"]
git-tree-sha1 = "299dc33549f68299137e51e6d49a13b5b1da9673"
uuid = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
version = "1.16.1"

[[deps.FilePaths]]
deps = ["FilePathsBase", "MacroTools", "Reexport", "Requires"]
git-tree-sha1 = "919d9412dbf53a2e6fe74af62a73ceed0bce0629"
uuid = "8fc22ac5-c921-52a6-82fd-178b2807b824"
version = "0.8.3"

[[deps.FilePathsBase]]
deps = ["Compat", "Dates", "Mmap", "Printf", "Test", "UUIDs"]
git-tree-sha1 = "e27c4ebe80e8699540f2d6c805cc12203b614f12"
uuid = "48062228-2e41-5def-b9a4-89aafe57970f"
version = "0.9.20"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[deps.FillArrays]]
deps = ["LinearAlgebra", "Random", "SparseArrays", "Statistics"]
git-tree-sha1 = "0b3b52afd0f87b0a3f5ada0466352d125c9db458"
uuid = "1a297f60-69ca-5386-bcde-b61e274b549b"
version = "1.2.1"

[[deps.Flux]]
deps = ["Adapt", "CUDA", "ChainRulesCore", "Functors", "LinearAlgebra", "MLUtils", "MacroTools", "NNlib", "NNlibCUDA", "OneHotArrays", "Optimisers", "Preferences", "ProgressLogging", "Random", "Reexport", "SparseArrays", "SpecialFunctions", "Statistics", "Zygote", "cuDNN"]
git-tree-sha1 = "3e2c3704c2173ab4b1935362384ca878b53d4c34"
uuid = "587475ba-b771-5e3f-ad9e-33799f191a9c"
version = "0.13.17"

    [deps.Flux.extensions]
    AMDGPUExt = "AMDGPU"
    FluxMetalExt = "Metal"

    [deps.Flux.weakdeps]
    AMDGPU = "21141c5a-9bdb-4563-92ae-f87d6854732e"
    Metal = "dde4c033-4e86-420c-a63e-0dd931031962"

[[deps.Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[deps.ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions"]
git-tree-sha1 = "00e252f4d706b3d55a8863432e742bf5717b498d"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "0.10.35"
weakdeps = ["StaticArrays"]

    [deps.ForwardDiff.extensions]
    ForwardDiffStaticArraysExt = "StaticArrays"

[[deps.Functors]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "478f8c3145bb91d82c2cf20433e8c1b30df454cc"
uuid = "d9f16b24-f501-4c13-a1f2-28368ffc5196"
version = "0.4.4"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[deps.GPUArrays]]
deps = ["Adapt", "GPUArraysCore", "LLVM", "LinearAlgebra", "Printf", "Random", "Reexport", "Serialization", "Statistics"]
git-tree-sha1 = "2e57b4a4f9cc15e85a24d603256fe08e527f48d1"
uuid = "0c68f7d7-f131-5f86-a1c3-88cf8149b2d7"
version = "8.8.1"

[[deps.GPUArraysCore]]
deps = ["Adapt"]
git-tree-sha1 = "2d6ca471a6c7b536127afccfa7564b5b39227fe0"
uuid = "46192b85-c4d5-4398-a991-12ede77f4527"
version = "0.1.5"

[[deps.GPUCompiler]]
deps = ["ExprTools", "InteractiveUtils", "LLVM", "Libdl", "Logging", "Scratch", "TimerOutputs", "UUIDs"]
git-tree-sha1 = "d60b5fe7333b5fa41a0378ead6614f1ab51cf6d0"
uuid = "61eb1bfa-7361-4325-ad38-22787b887f55"
version = "0.21.3"

[[deps.HTTP]]
deps = ["Base64", "CodecZlib", "ConcurrentUtilities", "Dates", "Logging", "LoggingExtras", "MbedTLS", "NetworkOptions", "OpenSSL", "Random", "SimpleBufferStream", "Sockets", "URIs", "UUIDs"]
git-tree-sha1 = "5e77dbf117412d4f164a464d610ee6050cc75272"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "1.9.6"

[[deps.IRTools]]
deps = ["InteractiveUtils", "MacroTools", "Test"]
git-tree-sha1 = "eac00994ce3229a464c2847e956d77a2c64ad3a5"
uuid = "7869d1d1-7146-5819-86e3-90919afe41df"
version = "0.4.10"

[[deps.InitialValues]]
git-tree-sha1 = "4da0f88e9a39111c2fa3add390ab15f3a44f3ca3"
uuid = "22cec73e-a1b8-11e9-2c92-598750a2cf9c"
version = "0.3.1"

[[deps.InlineStrings]]
deps = ["Parsers"]
git-tree-sha1 = "9cc2baf75c6d09f9da536ddf58eb2f29dedaf461"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.4.0"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.InvertedIndices]]
git-tree-sha1 = "0dc7b50b8d436461be01300fd8cd45aa0274b038"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.3.0"

[[deps.IrrationalConstants]]
git-tree-sha1 = "630b497eafcc20001bba38a4651b327dcfc491d2"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.2.2"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "abc9885a7ca2052a736a600f7fa66209f96506e1"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.4.1"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "31e996f0a15c7b280ba9f76636b3ff9e2ae58c9a"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.4"

[[deps.JSONSchema]]
deps = ["Downloads", "HTTP", "JSON", "URIs"]
git-tree-sha1 = "58cb291b01508293f7a9dc88325bc00d797cf04d"
uuid = "7d188eb4-7ad8-530c-ae41-71a32a6d4692"
version = "1.1.0"

[[deps.JuliaVariables]]
deps = ["MLStyle", "NameResolution"]
git-tree-sha1 = "49fb3cb53362ddadb4415e9b73926d6b40709e70"
uuid = "b14d175d-62b4-44ba-8fb7-3064adc8c3ec"
version = "0.2.4"

[[deps.KernelAbstractions]]
deps = ["Adapt", "Atomix", "InteractiveUtils", "LinearAlgebra", "MacroTools", "PrecompileTools", "SparseArrays", "StaticArrays", "UUIDs", "UnsafeAtomics", "UnsafeAtomicsLLVM"]
git-tree-sha1 = "b48617c5d764908b5fac493cd907cf33cc11eec1"
uuid = "63c18a36-062a-441e-b654-da1e3ab1ce7c"
version = "0.9.6"

[[deps.LLVM]]
deps = ["CEnum", "LLVMExtra_jll", "Libdl", "Printf", "Unicode"]
git-tree-sha1 = "7d5788011dd273788146d40eb5b1fbdc199d0296"
uuid = "929cbde3-209d-540e-8aea-75f648917ca0"
version = "6.0.1"

[[deps.LLVMExtra_jll]]
deps = ["Artifacts", "JLLWrappers", "LazyArtifacts", "Libdl", "TOML"]
git-tree-sha1 = "1222116d7313cdefecf3d45a2bc1a89c4e7c9217"
uuid = "dad2f222-ce93-54a1-a47d-0025e8a3acab"
version = "0.0.22+0"

[[deps.LaTeXStrings]]
git-tree-sha1 = "f2355693d6778a178ade15952b7ac47a4ff97996"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.3.0"

[[deps.LazyArtifacts]]
deps = ["Artifacts", "Pkg"]
uuid = "4af54fe1-eca0-43a8-85a7-787d91b784e3"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.3"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "7.84.0+0"

[[deps.LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.10.2+0"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.LogExpFunctions]]
deps = ["DocStringExtensions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "c3ce8e7420b3a6e071e0fe4745f5d4300e37b13f"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.24"

    [deps.LogExpFunctions.extensions]
    LogExpFunctionsChainRulesCoreExt = "ChainRulesCore"
    LogExpFunctionsChangesOfVariablesExt = "ChangesOfVariables"
    LogExpFunctionsInverseFunctionsExt = "InverseFunctions"

    [deps.LogExpFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ChangesOfVariables = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.LoggingExtras]]
deps = ["Dates", "Logging"]
git-tree-sha1 = "cedb76b37bc5a6c702ade66be44f831fa23c681e"
uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
version = "1.0.0"

[[deps.MLStyle]]
git-tree-sha1 = "bc38dff0548128765760c79eb7388a4b37fae2c8"
uuid = "d8e11817-5142-5d16-987a-aa16d5891078"
version = "0.4.17"

[[deps.MLUtils]]
deps = ["ChainRulesCore", "Compat", "DataAPI", "DelimitedFiles", "FLoops", "NNlib", "Random", "ShowCases", "SimpleTraits", "Statistics", "StatsBase", "Tables", "Transducers"]
git-tree-sha1 = "3504cdb8c2bc05bde4d4b09a81b01df88fcbbba0"
uuid = "f1d291b0-491e-4a28-83b9-f70985020b54"
version = "0.4.3"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "42324d08725e200c23d4dfb549e0d5d89dede2d2"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.10"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "MozillaCACerts_jll", "Random", "Sockets"]
git-tree-sha1 = "03a9b9718f5682ecb107ac9f7308991db4ce395b"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.1.7"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.2+0"

[[deps.MicroCollections]]
deps = ["BangBang", "InitialValues", "Setfield"]
git-tree-sha1 = "629afd7d10dbc6935ec59b32daeb33bc4460a42e"
uuid = "128add7d-3638-4c79-886c-908ea0c25c34"
version = "0.1.4"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "f66bdc5de519e8f8ae43bdc598782d35a25b1272"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.1.0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2022.10.11"

[[deps.NNlib]]
deps = ["Adapt", "Atomix", "ChainRulesCore", "GPUArraysCore", "KernelAbstractions", "LinearAlgebra", "Pkg", "Random", "Requires", "Statistics"]
git-tree-sha1 = "72240e3f5ca031937bd536182cb2c031da5f46dd"
uuid = "872c559c-99b0-510c-b3b7-b6c96a88d5cd"
version = "0.8.21"

    [deps.NNlib.extensions]
    NNlibAMDGPUExt = "AMDGPU"

    [deps.NNlib.weakdeps]
    AMDGPU = "21141c5a-9bdb-4563-92ae-f87d6854732e"

[[deps.NNlibCUDA]]
deps = ["Adapt", "CUDA", "LinearAlgebra", "NNlib", "Random", "Statistics", "cuDNN"]
git-tree-sha1 = "f94a9684394ff0d325cc12b06da7032d8be01aaf"
uuid = "a00861dc-f156-4864-bf3c-e6376f28a68d"
version = "0.2.7"

[[deps.NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "0877504529a3e5c3343c6f8b4c0381e57e4387e4"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.0.2"

[[deps.NameResolution]]
deps = ["PrettyPrint"]
git-tree-sha1 = "1a0fa0e9613f46c9b8c11eee38ebb4f590013c5e"
uuid = "71a1bf82-56d0-4bbc-8a3c-48b961074391"
version = "0.1.5"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[deps.NodeJS]]
deps = ["Pkg"]
git-tree-sha1 = "bf1f49fd62754064bc42490a8ddc2aa3694a8e7a"
uuid = "2bd173c7-0d6d-553b-b6af-13a54713934c"
version = "2.0.0"

[[deps.OneHotArrays]]
deps = ["Adapt", "ChainRulesCore", "Compat", "GPUArraysCore", "LinearAlgebra", "NNlib"]
git-tree-sha1 = "5e4029759e8699ec12ebdf8721e51a659443403c"
uuid = "0b1bfda6-eb8a-41d2-88d8-f5af5cad476f"
version = "0.2.4"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.21+4"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"
version = "0.8.1+0"

[[deps.OpenSSL]]
deps = ["BitFlags", "Dates", "MozillaCACerts_jll", "OpenSSL_jll", "Sockets"]
git-tree-sha1 = "51901a49222b09e3743c65b8847687ae5fc78eb2"
uuid = "4d8831e6-92b7-49fb-bdf8-b643e874388c"
version = "1.4.1"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "cae3153c7f6cf3f069a853883fd1919a6e5bab5b"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "3.0.9+0"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[deps.Optimisers]]
deps = ["ChainRulesCore", "Functors", "LinearAlgebra", "Random", "Statistics"]
git-tree-sha1 = "6a01f65dd8583dee82eecc2a19b0ff21521aa749"
uuid = "3bd65402-5787-11e9-1adc-39752487f4e2"
version = "0.2.18"

[[deps.OrderedCollections]]
git-tree-sha1 = "d321bf2de576bf25ec4d3e4360faca399afca282"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.6.0"

[[deps.Parsers]]
deps = ["Dates", "PrecompileTools", "UUIDs"]
git-tree-sha1 = "5a6ab2f64388fd1175effdf73fe5933ef1e0bac0"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.7.0"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "FileWatching", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.9.0"

[[deps.PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "a6062fe4063cdafe78f4a0a81cfffb89721b30e7"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.2"

[[deps.PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "9673d39decc5feece56ef3940e5dafba15ba0f81"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.1.2"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "7eb1686b4f04b82f96ed7a4ea5890a4f0c7a09f1"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.4.0"

[[deps.PrettyPrint]]
git-tree-sha1 = "632eb4abab3449ab30c5e1afaa874f0b98b586e4"
uuid = "8162dcfd-2161-5ef2-ae6c-7681170c5f98"
version = "0.2.0"

[[deps.PrettyTables]]
deps = ["Crayons", "Formatting", "LaTeXStrings", "Markdown", "Reexport", "StringManipulation", "Tables"]
git-tree-sha1 = "213579618ec1f42dea7dd637a42785a608b1ea9c"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "2.2.4"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.ProgressLogging]]
deps = ["Logging", "SHA", "UUIDs"]
git-tree-sha1 = "80d919dee55b9c50e8d9e2da5eeafff3fe58b539"
uuid = "33c8b6b6-d38a-422a-b730-caa89a2f386c"
version = "0.1.4"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.Random123]]
deps = ["Random", "RandomNumbers"]
git-tree-sha1 = "552f30e847641591ba3f39fd1bed559b9deb0ef3"
uuid = "74087812-796a-5b5d-8853-05524746bad3"
version = "1.6.1"

[[deps.RandomNumbers]]
deps = ["Random", "Requires"]
git-tree-sha1 = "043da614cc7e95c703498a491e2c21f58a2b8111"
uuid = "e6cf234a-135c-5ec9-84dd-332b85af5143"
version = "1.5.3"

[[deps.RealDot]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "9f0a1b71baaf7650f4fa8a1d168c7fb6ee41f0c9"
uuid = "c1ae055f-0cd5-4b69-90a6-9a35b1a98df9"
version = "0.1.0"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "838a3a4188e2ded87a4f9f184b4b0d78a1e91cb7"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.0"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.Scratch]]
deps = ["Dates"]
git-tree-sha1 = "30449ee12237627992a99d5e30ae63e4d78cd24a"
uuid = "6c6a2e73-6563-6170-7368-637461726353"
version = "1.2.0"

[[deps.SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "04bdff0b09c65ff3e06a05e3eb7b120223da3d39"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.4.0"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.Setfield]]
deps = ["ConstructionBase", "Future", "MacroTools", "StaticArraysCore"]
git-tree-sha1 = "e2cc6d8c88613c05e1defb55170bf5ff211fbeac"
uuid = "efcf1570-3423-57d1-acb7-fd33fddbac46"
version = "1.1.1"

[[deps.ShowCases]]
git-tree-sha1 = "7f534ad62ab2bd48591bdeac81994ea8c445e4a5"
uuid = "605ecd9f-84a6-4c9e-81e2-4798472b76a3"
version = "0.1.0"

[[deps.SimpleBufferStream]]
git-tree-sha1 = "874e8867b33a00e784c8a7e4b60afe9e037b74e1"
uuid = "777ac1f9-54b0-4bf8-805c-2214025038e7"
version = "1.1.0"

[[deps.SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "5d7e3f4e11935503d3ecaf7186eac40602e7d231"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.4"

[[deps.SnoopPrecompile]]
deps = ["Preferences"]
git-tree-sha1 = "e760a70afdcd461cf01a575947738d359234665c"
uuid = "66db9d55-30c0-4569-8b51-7e840670fc0c"
version = "1.0.3"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "c60ec5c62180f27efea3ba2908480f8055e17cee"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.1.1"

[[deps.SparseArrays]]
deps = ["Libdl", "LinearAlgebra", "Random", "Serialization", "SuiteSparse_jll"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.SpecialFunctions]]
deps = ["IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "7beb031cf8145577fbccacd94b8a8f4ce78428d3"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.3.0"
weakdeps = ["ChainRulesCore"]

    [deps.SpecialFunctions.extensions]
    SpecialFunctionsChainRulesCoreExt = "ChainRulesCore"

[[deps.SplittablesBase]]
deps = ["Setfield", "Test"]
git-tree-sha1 = "e08a62abc517eb79667d0a29dc08a3b589516bb5"
uuid = "171d559e-b47b-412a-8079-5efa626c420e"
version = "0.1.15"

[[deps.StaticArrays]]
deps = ["LinearAlgebra", "Random", "StaticArraysCore"]
git-tree-sha1 = "0da7e6b70d1bb40b1ace3b576da9ea2992f76318"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.6.0"
weakdeps = ["Statistics"]

    [deps.StaticArrays.extensions]
    StaticArraysStatisticsExt = "Statistics"

[[deps.StaticArraysCore]]
git-tree-sha1 = "6b7ba252635a5eff6a0b0664a41ee140a1c9e72a"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.0"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.9.0"

[[deps.StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "45a7769a04a3cf80da1c1c7c60caf932e6f4c9f7"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.6.0"

[[deps.StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "75ebe04c5bed70b91614d684259b661c9e6274a4"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.34.0"

[[deps.StringManipulation]]
git-tree-sha1 = "46da2434b41f41ac3594ee9816ce5541c6096123"
uuid = "892a3eda-7b42-436c-8928-eab12a02cf0e"
version = "0.3.0"

[[deps.StructArrays]]
deps = ["Adapt", "DataAPI", "GPUArraysCore", "StaticArraysCore", "Tables"]
git-tree-sha1 = "521a0e828e98bb69042fec1809c1b5a680eb7389"
uuid = "09ab397b-f2b6-538f-b94a-2f83cf4a842a"
version = "0.6.15"

[[deps.SuiteSparse_jll]]
deps = ["Artifacts", "Libdl", "Pkg", "libblastrampoline_jll"]
uuid = "bea87d4a-7f5b-5778-9afe-8cc45184846c"
version = "5.10.1+6"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.TableTraitsUtils]]
deps = ["DataValues", "IteratorInterfaceExtensions", "Missings", "TableTraits"]
git-tree-sha1 = "78fecfe140d7abb480b53a44f3f85b6aa373c293"
uuid = "382cd787-c1b6-5bf2-a167-d5b971a19bda"
version = "1.0.2"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits", "Test"]
git-tree-sha1 = "1544b926975372da01227b382066ab70e574a3ec"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.10.1"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.0"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.TimerOutputs]]
deps = ["ExprTools", "Printf"]
git-tree-sha1 = "f548a9e9c490030e545f72074a41edfd0e5bcdd7"
uuid = "a759f4b9-e2f1-59dc-863e-4aeb61b1ea8f"
version = "0.5.23"

[[deps.TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "9a6ae7ed916312b41236fcef7e0af564ef934769"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.13"

[[deps.Transducers]]
deps = ["Adapt", "ArgCheck", "BangBang", "Baselet", "CompositionsBase", "DefineSingletons", "Distributed", "InitialValues", "Logging", "Markdown", "MicroCollections", "Requires", "Setfield", "SplittablesBase", "Tables"]
git-tree-sha1 = "a66fb81baec325cf6ccafa243af573b031e87b00"
uuid = "28d57a85-8fef-5791-bfe6-a80928e7c999"
version = "0.4.77"

    [deps.Transducers.extensions]
    TransducersBlockArraysExt = "BlockArrays"
    TransducersDataFramesExt = "DataFrames"
    TransducersLazyArraysExt = "LazyArrays"
    TransducersOnlineStatsBaseExt = "OnlineStatsBase"
    TransducersReferenceablesExt = "Referenceables"

    [deps.Transducers.weakdeps]
    BlockArrays = "8e7c35d0-a365-5155-bbbb-fb81a777f24e"
    DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
    LazyArrays = "5078a376-72f3-5289-bfd5-ec5146d43c02"
    OnlineStatsBase = "925886fa-5bf2-5e8e-b522-a9147a512338"
    Referenceables = "42d2dcc6-99eb-4e98-b66c-637b7d73030e"

[[deps.URIParser]]
deps = ["Unicode"]
git-tree-sha1 = "53a9f49546b8d2dd2e688d216421d050c9a31d0d"
uuid = "30578b45-9adc-5946-b283-645ec420af67"
version = "0.4.1"

[[deps.URIs]]
git-tree-sha1 = "074f993b0ca030848b897beff716d93aca60f06a"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.4.2"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.UnsafeAtomics]]
git-tree-sha1 = "6331ac3440856ea1988316b46045303bef658278"
uuid = "013be700-e6cd-48c3-b4a1-df204f14c38f"
version = "0.2.1"

[[deps.UnsafeAtomicsLLVM]]
deps = ["LLVM", "UnsafeAtomics"]
git-tree-sha1 = "323e3d0acf5e78a56dfae7bd8928c989b4f3083e"
uuid = "d80eeb9a-aca5-4d75-85e5-170c8b632249"
version = "0.1.3"

[[deps.Vega]]
deps = ["BufferedStreams", "DataStructures", "DataValues", "Dates", "FileIO", "FilePaths", "IteratorInterfaceExtensions", "JSON", "JSONSchema", "MacroTools", "NodeJS", "Pkg", "REPL", "Random", "Setfield", "TableTraits", "TableTraitsUtils", "URIParser"]
git-tree-sha1 = "9d5c73642d291cb5aa34eb47b9d71428c4132398"
uuid = "239c3e63-733f-47ad-beb7-a12fde22c578"
version = "2.6.2"

[[deps.VegaLite]]
deps = ["Base64", "BufferedStreams", "DataStructures", "DataValues", "Dates", "FileIO", "FilePaths", "IteratorInterfaceExtensions", "JSON", "MacroTools", "NodeJS", "Pkg", "REPL", "Random", "TableTraits", "TableTraitsUtils", "URIParser", "Vega"]
git-tree-sha1 = "3dc847d4bc5766172b4646fd7fe6a99bff53ac7b"
uuid = "112f6efa-9a02-5b7d-90c0-432ed331239a"
version = "3.2.2"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.13+0"

[[deps.Zygote]]
deps = ["AbstractFFTs", "ChainRules", "ChainRulesCore", "DiffRules", "Distributed", "FillArrays", "ForwardDiff", "GPUArrays", "GPUArraysCore", "IRTools", "InteractiveUtils", "LinearAlgebra", "LogExpFunctions", "MacroTools", "NaNMath", "PrecompileTools", "Random", "Requires", "SparseArrays", "SpecialFunctions", "Statistics", "ZygoteRules"]
git-tree-sha1 = "5be3ddb88fc992a7d8ea96c3f10a49a7e98ebc7b"
uuid = "e88e6eb3-aa80-5325-afca-941959d7151f"
version = "0.6.62"

    [deps.Zygote.extensions]
    ZygoteColorsExt = "Colors"
    ZygoteDistancesExt = "Distances"
    ZygoteTrackerExt = "Tracker"

    [deps.Zygote.weakdeps]
    Colors = "5ae59095-9a9b-59fe-a467-6f913c188581"
    Distances = "b4f34e82-e78d-54a5-968a-f98e89d6e8f7"
    Tracker = "9f7883ad-71c0-57eb-9f7f-b5c9e6d3789c"

[[deps.ZygoteRules]]
deps = ["ChainRulesCore", "MacroTools"]
git-tree-sha1 = "977aed5d006b840e2e40c0b48984f7463109046d"
uuid = "700de1a5-db45-46bc-99cf-38207098b444"
version = "0.2.3"

[[deps.cuDNN]]
deps = ["CEnum", "CUDA", "CUDNN_jll"]
git-tree-sha1 = "ee79f97d07bf875231559f9b3f2649f34fac140b"
uuid = "02a925ec-e4fe-4b08-9a7e-0d78e3d38ccd"
version = "1.1.0"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.7.0+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.48.0+0"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+0"
"""

# ╔═╡ Cell order:
# ╟─4a8964c9-8c07-4e1c-a635-24dcd62436e3
# ╠═ede5bca4-183b-11ee-20c6-db7b4b6ebe30
# ╟─7629b1e1-061b-4f39-ab0b-5d45b1c417e6
# ╠═c019c571-284e-4296-8b45-1ee7355a4471
# ╠═f3f5a8f4-a9cf-4103-a013-7c37158a34a1
# ╠═477de20d-938a-43ed-a8be-c54703146d04
# ╟─6bbf347d-0e6d-4993-aee5-59673b4f1ba6
# ╟─c52825e6-d1e8-45a2-8502-5334264101ec
# ╠═b0f80e35-cc97-4c4c-81f4-c622d5c4fcd5
# ╟─6716974c-7ebe-49bd-9df5-698b1af168b5
# ╟─cac68ab1-b490-4233-ba2c-aecb4b899cd2
# ╠═278ac348-2c3f-4471-98cf-b7c3842b55ba
# ╟─369d34ad-946a-4cc2-9e2c-74f240334845
# ╟─444b047c-ec47-42ae-9b06-bd35fedb092f
# ╠═160910d5-a6be-42ba-b666-62fb89bb9f00
# ╠═211c8e12-1793-4744-96ed-149cb18d91f8
# ╟─989db75a-f130-4753-8409-7c5c04a46453
# ╟─b8db2df8-7c91-4bcd-9f28-d84645f24d08
# ╠═801c3a8f-7af8-42b6-b347-a732b81c7ac6
# ╟─1334dbf9-1496-4da8-865b-a0c9c1bbebab
# ╠═4f4f2169-0683-4ec7-8998-c58b1f793642
# ╠═3ae52bbe-4de4-4fda-8595-e23e766640db
# ╟─412d51ce-79dd-4b67-9617-bfed6b2f304f
# ╠═be94bf72-6c4e-45d6-9428-b25c46455821
# ╟─ff4870dc-a50e-4aae-97e1-9cfbad1741d7
# ╠═f15879db-cda5-4591-a2d8-33b09b5e6c75
# ╟─fc47a9b3-87a8-464c-91de-9a33969cab99
# ╠═b1d355f6-e86a-4e1b-9527-135432dd3fc9
# ╟─485ab7a7-97cc-4b6d-bae2-830bcc0f65e2
# ╠═46fee057-ac27-4e19-9ed0-e592b63bd278
# ╟─ddbb2e17-4b4d-4386-a690-eb5f2ea7bad8
# ╠═14f6bdb6-dd4e-4fb6-917e-a7e5fb9e25b9
# ╠═8b358d53-a3c0-4f49-9544-80635627d331
# ╠═887cc9c8-cfe0-46cb-aa1b-efc0cd041bb9
# ╟─7b31217f-1170-496a-a43f-93e26bfc0fa2
# ╟─f7d37dce-1e6d-4753-ba67-a7849d1e6a36
# ╠═aeef3e40-f119-4806-a1d7-89245277ad18
# ╠═a9ee941a-d8d8-4052-8f5a-5ea6710a5ba8
# ╟─7ba30f29-37dc-4e91-8c19-67d8c481d9b2
# ╟─8dea8490-cb8e-41cb-b71f-7d72a2c2b807
# ╟─9e830453-e885-44b5-bb59-cf3592606c5f
# ╟─fb0af0bc-bbb0-44e5-b157-e5d9fc4b37bb
# ╠═4cc38a5f-8779-43c1-b229-985f04f37000
# ╟─0a7d66d1-b7ee-4230-9d36-80d9b880c064
# ╟─75cca775-e06e-4f76-924f-319e0b1b2303
# ╠═6430852c-1913-47d2-9aea-b23fd489b970
# ╟─ac33ad3f-5017-4e4f-8cf8-e471aeea418d
# ╟─9528f8c4-6182-4e4c-a7b3-31f826a328d2
# ╠═df6d904a-6126-40cf-932c-f8080477cbaf
# ╠═f6d6640c-104b-4d83-a9cc-a67cf279c8bc
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
