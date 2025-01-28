# Piston Engine Nasal Simulation, adapted from the Cessna 172P
# Manages the engine
#
# Fuel system: based on the Spitfire. Manages primer and negGCutoff
# Hobbs meter

# =============================== DEFINITIONS ===========================================

# set the update period

var UPDATE_PERIOD = 0.3;

# ============================= GLOBAL VARIABLES ====================================
var complex_procedures = 0;

setlistener("/engines/engine[0]/complex-engine-procedures", func(i) {
	complex_procedures = i.getIntValue();
	# Create a new fuel contamination situation
	fuel_contamination();
});

# ========== primer stuff ======================

# Toggles the state of the primer
var pumpPrimer = func {
	var push = getprop("/controls/engines/engine/primer-lever") or 0;
	
	if (push) {
		var pump = getprop("/controls/engines/engine/primer") or 0;
		setprop("/controls/engines/engine/primer", pump + 1);
		setprop("/controls/engines/engine/primer-lever", 0);
	}
	else {
		setprop("/controls/engines/engine/primer-lever", 1);
	}
};

# Primes the engine automatically. This function takes several seconds
var autoPrime = func {
	var p = getprop("/controls/engines/engine/primer") or 0;
	if (p < 3) {
		pumpPrimer();
		settimer(autoPrime, 1);
	}
};

# Mixture will be calculated using the primer during 5 seconds AFTER the pilot used the starter
# This prevents the engine to start just after releasing the starter: the propeller will be running
# thanks to the electric starter, but carburator has not yet enough mixture
var primerTimer = maketimer(5, func {
	setprop("/controls/engines/engine/use-primer", 0);
	# Reset the number of times the pilot used the primer only AFTER using the starter
	setprop("/controls/engines/engine/primer", 0);
	debug_print("Primer reset to 0");
	primerTimer.stop();
});

# ========== oil consumption ======================
# Thanks to HHS81 (Benedikt Hallinger) for more advanced simulation
var service_hours = getprop("/engines/engine[0]/oil-service-hours");
var consumption_qps = 0.0;
var rpm_factor = 0.0;
var rpm = 0;
var oil_level = 0;
var oil_full = 0;
var oil_lacking = 0;
var oil_level_limited = 0;
var service_hours_increase_qph = 0;
var service_hours_new = 0;
var low_oil_pressure_factor = 0.0;
var low_oil_temperature_factor = 0.0;

# ======= OIL SYSTEM INIT =======
if (!getprop("/engines/engine[0]/oil-service-hours")) {
	setprop("/engines/engine[0]/oil-service-hours", 0);
}

#	Oil used:	(Continental Overhaul Manual p.109)
#		according to Continental Motors Specification MHS-24A
#		below 40 degF:	SAE.40
#		above 40 degF:	SAE 20 or SAE 10 W 30
#		example: https://www.shell-livedocs.com/data/published/en/f2bece04-2823-4497-90bf-3f58facde57d.pdf 
#			density: 857 kg/m3 -> 857 kg/m3 * 2,205 lbs/kg / 879,877 qt/kg = 2.15 lbs/qt

var oil_consumption = maketimer(1.0, func {
	
	oil_level = getprop("/engines/engine[0]/oil-level");
	if (getprop("/controls/engines/engine[0]") == 0)
		oil_full = 7;
	if (getprop("/controls/engines/engine[0]") == 1)
		oil_full = 8;
	oil_lacking = oil_full - oil_level;
	setprop("/engines/engine[0]/oil-lacking", oil_lacking);
	
	if ( complex_procedures ) {
		
		rpm = getprop("/engines/engine[0]/rpm");
		
		# Quadratic formula which outputs 1.0 for maximum RPM (2750 RPM)
		rpm_factor = 0.00000012 * math.pow(rpm, 2) - 0.0001 * rpm + 0.3675;
		
		# Maximum Oil Consumption 0.80 lbs/hr = 0.37 qt/hr ->  (Continental Overhaul Manual p.109)
		consumption_qps = 0.37 / 3600;
		
		# Raise consumption when oil level is > 6 quarts (blowout)
		if (oil_level > oil_full) {
			consumption_qps = consumption_qps * 1.3;
		}
		
		# Consumption also raises with oil in service time (lower viscosity => more friction)
		# (Oil should be changed at 50 hrs!)
		# See: http://www.t-craft.org/Reference/Aircraft.Oil.Usage.pdf
		# Hours:        0 |    10 |    25 |  50   |    75
		# Add Qts/hr:   0 |  0.02 | 0.125 | 0.5   | 1.125
		service_hours = getprop("/engines/engine[0]/oil-service-hours");
		service_hours_increase_qph = 0.00020 * math.pow(service_hours, 2);
		service_hours_increase_qph = std.min(1.5, service_hours_increase_qph); # limit increase to 1.5 (at which point you really should think of changing it)
		service_hours_increase_qps = service_hours_increase_qph / 3600;
		consumption_qps = consumption_qps + service_hours_increase_qps;

		if (getprop("/engines/engine[0]/running")) {
			oil_level = oil_level - consumption_qps * rpm_factor;
			setprop("/engines/engine[0]/oil-level", oil_level);
			setprop("/engines/engine[0]/oil-consume-qps", consumption_qps);
			setprop("/engines/engine[0]/oil-consume-qph", consumption_qps * 3600);
			
			service_hours_new = (service_hours * 3600 + 1) / 3600; # add one second service time
			setprop("/engines/engine[0]/oil-service-hours", service_hours_new);
		} else {
			setprop("/engines/engine[0]/oil-consume-qps", 0);
		}

		low_oil_pressure_factor = 1.0;
		low_oil_temperature_factor = 1.0;

		# If oil gets low (< 3.0), pressure should drop and temperature should rise
		oil_level_limited = std.min(oil_level, 3.0);

		# Should give 1.0 for oil_level = 3 and 0.1 for oil_level 1.97,
		# which is the min before the engine stops
		low_oil_pressure_factor = 0.873786408 * oil_level_limited - 1.621359224;

		# Should give 1.0 for oil_level = 3 and 1.5 for oil_level 1.97
		low_oil_temperature_factor = -0.485436893 * oil_level_limited + 2.456310679;

		setprop("/engines/engine[0]/low-oil-pressure-factor", low_oil_pressure_factor);
		setprop("/engines/engine[0]/low-oil-temperature-factor", low_oil_temperature_factor);
	}
	
	else {
		# if oil consumption is not allowed, the oil level is set to full and pressure and temp factors are set to 1.0
		setprop("/engines/engine[0]/oil-level", 6);
		setprop("/engines/engine[0]/low-oil-pressure-factor", 1.0);
		setprop("/engines/engine[0]/low-oil-temperature-factor", 1.0);
	}
});

# Oil Refilling
var oil_refill = func(){
	var previous_oil_level = getprop("/engines/engine[0]/oil-level");
	var service_hours = getprop("/engines/engine[0]/oil-service-hours");
	var oil_level     = getprop("/engines/engine[0]/oil-level");
	var refilled      = oil_level - previous_oil_level;
	#print("OIL Refill init: svcHrs=", service_hours, "; oil_level=",oil_level, "; previous_oil_level=",previous_oil_level, "; refilled=",refilled);
	
	if (refilled >= 0) {
		# when refill occured, the new oil "makes the old oil younger"
		var pct = 0;
		if (oil_level > 0) {
			pct = previous_oil_level / oil_level;
		}
		var newService_hours = service_hours * pct;
		setprop("/engines/engine[0]/oil-service-hours", newService_hours);
		#print("OIL Refill: pct=", pct, "; service_hours=",service_hours, "; newService_hours=", newService_hours, "; previous_oil_level=", previous_oil_level, "; oil_level=",oil_level);
	}
	
	previous_oil_level = oil_level;
}

# ======= Oil temperature jsbsim compensator =======
# Currently, jsbsim oil temperature always initializes at 60°F.
# We want an temperature that initialize to environment temperature until first start
# and then gradually switch over to the real jsbsim value after some time.
var calculate_real_oiltemp = maketimer(0.5, func {
	if (!getprop("/engines/engine[0]/already-started-in-session")) {
		# engine is still cold
		var temp_env        = getprop("/environment/temperature-degf") or 60;
		var temp_jsbsim_oil = getprop("/engines/engine[0]/oil-temperature-degf") or 60;
		current_temp_diff   = temp_jsbsim_oil - temp_env;
		setprop("/engines/engine[0]/oil-temperature-env-diff", current_temp_diff);
	} else {
		# engine has been started at least one time:
		# gradually remove the difference as jsbsim adapts to real environment temperature
		calculate_real_oiltemp.stop();
		interpolate("/engines/engine[0]/oil-temperature-env-diff", 0, 180); # hand over to jsbsim caluclation gradually over 2 minutes
	}
});

# ========== carburetor icing ======================

var carb_icing_function = maketimer(1.0, func {
	if (getprop("/engines/engine[0]/carb_icing_allowed")) {
		var rpm = getprop("/engines/engine[0]/rpm");
		var dewpointC = getprop("/environment/dewpoint-degc");
		var dewpointF = dewpointC * 9.0 / 5.0 + 32;
		var airtempF = getprop("/environment/temperature-degf");
		var oil_temp = getprop("/engines/engine[0]/oil-temperature-degf");
		var egt_degf = getprop("/engines/engine[0]/egt-degf");
		var engine_running = getprop("/engines/engine[0]/running");
		var carb_ice = getprop("/engines/engine[0]/carb_ice");
		
		# the formula below attempts to model the graph found in the POH which relates air temperature, dew point and RPM to icing
		# conditions. The outputs of carb_icing_formula ranges from 0.65 to -0.35 (positive means ice is accumulating, negative
		# means that ice is melting)
		var factorX = 13.2 - 3.2 * math.atan2 ( ((rpm - 2000.0) * 0.008), 1);
		var factorY = 7.0 - 2.0 * math.atan2 ( ((rpm - 2000.0) * 0.008), 1);
		var carb_icing_formula = (math.exp( math.pow((0.6 * airtempF + 0.3 * dewpointF - 42.0),2) / (-2 * math.pow(factorX,2))) * math.exp( math.pow((0.3 * airtempF - 0.6 * dewpointF + 14.0),2) / (-2 * math.pow(factorY,2))) - 0.35)  * engine_running;
		
		# the efficacy of carb heat depends on the EGT. With a typical EGT of ~1500, the carb_heat_rate will be around -1.5.
		# This value is an educated guess of the RL effect, and should melt ice regardless of the icing rate
		if (getprop("/controls/engines/current-engine/carb-heat"))
			var carb_heat_rate = -0.001 * egt_degf;
		else
			var carb_heat_rate = 0.0;
		
		# a warm engine will accumulate less ice than a cold one, which is what oil temp factor is used for. oil_temp_factor
		# ranges from 0 to aprox -0.2 (at 250 oF). These values are educated guesses of the RL effect
		var oil_temp_factor = oil_temp / -1250;
		
		# the final rate of icing or melting is then calculated by all these effects together
		var carb_icing_rate = carb_icing_formula + carb_heat_rate + oil_temp_factor;
		
		# since the carb_icing_rate gives an arbitrary final value, the rate is then scaled down by 0.00001 to ensure ice
		# accumulates as slowly as expected
		carb_ice = carb_ice + carb_icing_rate * 0.00001;
		carb_ice = std.max(0.0, std.min(carb_ice, 1.0));
		
		# this property is used to lower the RPM of the engine as ice accumulates (more ice in the carburator == less power)
		var vol_eff_factor = std.max(0.0, 0.85 - 1.72 * carb_ice);
		
		setprop("/engines/engine[0]/carb_ice", carb_ice);
		setprop("/engines/engine[0]/carb_icing_rate", carb_icing_rate);
		setprop("/engines/engine[0]/volumetric-efficiency-factor", vol_eff_factor);
		setprop("/engines/engine[0]/oil_temp_factor", oil_temp_factor);
		
	}
	else {
		setprop("/engines/engine[0]/carb_ice", 0.0);
		setprop("/engines/engine[0]/carb_icing_rate", 0.0);
		setprop("/engines/engine[0]/volumetric-efficiency-factor", 0.85);
		setprop("/engines/engine[0]/oil_temp_factor", 0.0);
	};
});

# ========== engine coughing ======================

var engine_coughing = func(){
	
	var coughing = getprop("/engines/engine[0]/coughing");
	var running = getprop("/engines/engine[0]/running");
	
	if (coughing and running) {
		# the code below kills the engine and then brings it back to life after 0.25 seconds, simulating a cough
		setprop("/engines/engine[0]/kill-engine", 1);
		settimer(func {
			setprop("/engines/engine[0]/kill-engine", 0);
		}, 0.25);
	};
	
	# basic value for the delay (interval between consecutive coughs), in case no fuel contamination nor carb ice are present
	var delay = 2;
	
	# if coughing due to fuel contamination, then cough interval depends on quantity of water
	var water_contamination0 = getprop("/consumables/fuel/tank[0]/water-contamination");
	var water_contamination1 = getprop("/consumables/fuel/tank[1]/water-contamination");
	var total_water_contamination = std.min((water_contamination0 + water_contamination1), 0.4);
	if (total_water_contamination > 0) {
		# if contamination is near 0, then interval is between 17 and 20 seconds, but if contamination is near the
		# engine stopping value of 0.4, then interval falls to around 0.5 and 3.5 seconds
		delay = 3.0 * rand() + 17 - 41.25 * total_water_contamination;
	};
	
	# if coughing due to carb ice melting, then cough depends on quantity of ice in the carburettor
	var carb_ice = getprop("/engines/engine[0]/carb_ice");
	if (carb_ice > 0) {
		# if carb_ice is near 0, then interval is between 17 and 20 seconds, but if carb_ice is near the
		# engine stopping value of 0.3, then interval falls to around 0.5 and 3.5 seconds
		delay = 3.0 * rand() + 17 - 41.25 * carb_ice;
	};
	
	coughing_timer.restart(delay);
	
}

var coughing_timer = maketimer(1, engine_coughing);

# ====== Engine starting actions ======
var engine_starting = props.globals.initNode("/engines/engine/starting", 0, "BOOL");
setlistener("/engines/engine/running", func(ngn){
	if (ngn.getValue() and !getprop("/engines/engine[0]/coughing")) {
		engine_starting.setValue(1);
		var timer = maketimer(1, func(){
			engine_starting.setValue(0);
		});
		timer.singleShot = 1; # timer will only be run once
		timer.start();
	} else {
		engine_starting.setValue(0);
	}
},0,0);

setlistener("/engines/engine/starting", func(ngn){
	# Eye-candy: when engine starts, let the view shake a bit
	if (ngn.getValue() and getprop("/sim/current-view/internal")) {
		var curX = getprop("/sim/current-view/x-offset-m");
		var xtimer = maketimer(0.05, func(){
			interpolate("/sim/current-view/x-offset-m", curX-0.0015+rand()*0.003, 0.05);
		});
		xtimer.start();
		var curY = getprop("/sim/current-view/y-offset-m");
		var ytimer = maketimer(0.05, func(){
			interpolate("/sim/current-view/y-offset-m", curY-0.0015+rand()*0.003, 0.05);
		});
		ytimer.start();
		var stoptimer = maketimer(0.8, func(){
			xtimer.stop();
			ytimer.stop();
			interpolate("/sim/current-view/x-offset-m", curX, 0.1);
			interpolate("/sim/current-view/y-offset-m", curY, 0.1);
		});
		stoptimer.singleShot = 1;
		stoptimer.start();
	}
}, 0, 0);

##########################################
# Fuel Contamination
##########################################
var fuel_contamination = func {
	var chance = rand();
	
	# Chance of contamination is 1 %
	
	if ( complex_procedures and chance < 0.01) {
		# Quantity of water is much more likely to be small than large, since
		# it's given by x^6 (76 % of the time it will be lower than 0.2)
		var water = math.pow(rand(), 6);
		
		setprop("/consumables/fuel/tank[0]/water-contamination", water);
		
		# level of water in the right tank will be the same as in the left tank +- 0.1
		water = water + 0.2 * (rand() - 0.5);
		water = std.max(0.0, std.min(water, 1.0));
		setprop("/consumables/fuel/tank[1]/water-contamination", water);
	} else {
		setprop("/consumables/fuel/tank[0]/water-contamination", 0.0);
		setprop("/consumables/fuel/tank[1]/water-contamination", 0.0);
	};
};

##########################################
# Take Fuel Sample
##########################################
var take_fuel_sample = func(index) {
	var fuel = getprop("/consumables/fuel/tank", index, "level-gal_us");
	var water = getprop("/consumables/fuel/tank", index, "water-contamination");
	
	# Remove 50 ml of fuel
	setprop("/consumables/fuel/tank", index, "level-gal_us", fuel - 0.0132086);
	
	# Remove a bit of water if contaminated
	if (water > 0.0) {
		var sample_water = std.min(0.2, water);
		water = water - sample_water;
		# As the fuel strainer is the lowest point of the fuel system,
		# water is removed indirectly from the wing fuel tanks
		setprop("/consumables/fuel/tank[0]/water-contamination", water/2);
		setprop("/consumables/fuel/tank[1]/water-contamination", water/2);
		setprop("/consumables/fuel/tank", index, "sample-water-contamination", sample_water);
	} else {
		setprop("/consumables/fuel/tank", index, "sample-water-contamination", 0.0);
	}
};

# ========== Main loop ======================

var update = func {
	
	# We use the mixture to control the engines, so set the mixture
	var usePrimer = getprop("/controls/engines/engine/use-primer") or 0;
	
	var engine_running = getprop("/engines/engine[0]/running");
	
	if (usePrimer and !engine_running and getprop("/engines/engine[0]/oil-temperature-degf") <= 75) {
		# Mixture is controlled by start conditions
		var primer = getprop("/controls/engines/engine/primer");
		if (!getprop("/fdm/jsbsim/fcs/mixture-primer-cmd") and getprop("/systems/electrical/outputs/starter") >= 9) {
			if (primer < 3) {
				print("Use the primer!");
				gui.popupTip("Use the primer!");
			}
			elsif (primer > 6) {
				print("Flooded engine!");
				gui.popupTip("Flooded engine!");
			}
			else {
				print("Check the throttle!");
				gui.popupTip("Check the throttle!");
			}
		}
	}
	
	var rpm = getprop("/engines/engine[0]/rpm");
	
	# sorry - had to hack this to prevent coughing on startup due to the oil pressure simulation. Maybe this can be used elsewhere
	if (rpm < 900 and getprop("/controls/engines/engine[0]/starter") == 1) { # make sure it is not triggered if you accidentally hit s in the air
		setprop("/engines/engine[0]/ready-oil-press-checker", 1); # 0 = off, 1 = checker is armed, 2 = engine is running and ready
	}
	
	if (getprop("/engines/engine[0]/ready-oil-press-checker") == 1 and getprop("/engines/engine[0]/rpm") > 900) {
		setprop("/engines/engine[0]/ready-oil-press-checker", 2); # engine is ready for use
	}
};

setlistener("/controls/engines/engine[0]/starter", func {
	var v = getprop("/controls/engines/engine[0]/starter") or 0;
	if (v == 0) {
		debug_print("Starter off");
		# notice the starter will be reset after 5 seconds
		primerTimer.restart(5);
	} else {
		debug_print("Starter on");
		setprop("/controls/engines/engine/use-primer", 1);
		if (primerTimer.isRunning) {
			primerTimer.stop();
		}
	}
}, 1, 0);

# ================================ Initalize ======================================
# Make sure all needed properties are present and accounted
# for, and that they have sane default values.

setprop("/engines/engine[0]/rpm", 0);
setprop("/engines/engine[0]/ready-oil-press-checker", 0);


# key 's' calls to this function when it is pressed DOWN even if I overwrite the binding in the -set.xml file!
# fun fact: the key UP event can be overwriten!
controls.startEngine = func(v = 1) {
	# Only operate in non-walker mode ('s' is also bound to walk-backward)
	var view_name = getprop("/sim/current-view/name");
	if (view_name == getprop("/sim/view[110]/name") or view_name == getprop("/sim/view[111]/name")) {
		return;
	}
	if (getprop("/engines/engine[0]/running")) {
		setprop("/controls/engines/engine[0]/c150-magnetos", 3);
		return;
	} else {
		setprop("/controls/engines/engine[0]/c150-magnetos", 3 + v);
	}
};

var engine_timer = maketimer(UPDATE_PERIOD, func { update(); });
coughing_timer.singleShot = 1;
oil_consumption.simulatedTime = 1;

setlistener("/sim/signals/fdm-initialized", func {
	complex_procedures = getprop("/engines/engine[0]/complex-engine-procedures");
	engine_timer.start();
	carb_icing_function.start();
	coughing_timer.start();
	if (oil_consumption.isRunning) {
		oil_consumption.stop();
	}
	oil_consumption.start();
	calculate_real_oiltemp.start();
	# Checking if fuel contamination is allowed, and if so generating a random situation
	fuel_contamination();
});
