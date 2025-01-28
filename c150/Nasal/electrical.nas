##
# Procedural model of a Cessna 150 electrical system.  Includes a
# preliminary battery charge/discharge model and realistic ammeter
# gauge modeling.
#


var altSwN     = props.globals.getNode("/controls/engines/engine[0]/master-alt", 1);
var batSwN     = props.globals.getNode("/controls/engines/engine[0]/master-bat", 1);

var flaps_cmd	= props.globals.getNode("/controls/flight/flaps-cmd", 1);	#	-1 = up; 0 = off (no movement); 1 = down
var flaps_motor	= props.globals.getNode("/controls/flight/flaps-motor-factor", 1);
var flaps_pos	= props.globals.getNode("/controls/flight/flaps",     1);
var flaps_volts	= props.globals.getNode("/systems/electrical/outputs/flaps", 1);
	# Some joysticks for example don't call controls.flapDown(0); when the button is released, thus the default behaviour is stopping the movement at virtual "detents"
	# (0, 10, 20, 30 and 40 degrees), even though the real aircraft allows operating the flaps through the full range using the lever
var flaps_mode	= props.globals.getNode("/sim/model/c150/options/flap-mode", 1);	# 0 = stops at every detent, 1 = operates through full range (realistic)

var delta_time	= props.globals.getNode("sim/time/delta-sec", 1);

var overvoltage_light = props.globals.getNode("sim/model/c150/surtension-light", 1);

##
# Initialize internal values
#

var battery = nil;
var alternator = nil;

var last_time = 0.0;

var vbus_volts = 0.0;
var ebus1_volts = 0.0;
var ebus2_volts = 0.0;

var ammeter_ave = 0.0;

# helper objects

var pocSound = { 
	path : getprop("/sim/fg-root") ~ '/Sounds', 
	file : "click.wav" , 
	volume : 1.0
};


var Output = {
	new : func(name, property, switch = nil, breaker = nil, power = 1, masterbreaker = nil, masterswitch = nil,
		   potar = nil, novbus = 0) {
		var m = { parents : [Output] };
		m.name = name;
		m.property = property;
		m.switch = switch;
		m.potar = potar;
		m.breaker = breaker;
		m.power = power;
		m.masterbreaker = masterbreaker;
		m.masterswitch = masterswitch;
		m.novbus = novbus;
		return m;
		   },
};

var Breaker = {
	new : func(name, property, power = 1) {
		var m = { parents : [Breaker] };
		m.name = name;
		m.property = property;
		m.power = power + 0.1;
		m.load = 0;
		m.is_serviceable = props.globals.getNode( property, 1 );
		return m;
	},
	applyLoad : func(load) {
		me.load += load;
		if(me.load >= me.power and me.is_serviceable) {
			me.is_serviceable.setBoolValue( 0 );
			# using a tooltip is not possible because switches already use a tooltip
			setprop("sim/model/c150/breaker-name", me.name);
			fgcommand( "dialog-show", props.Node.new( "breakers-dialog" ) );
			#gui.popupTip("Warning: Check your circuit breakers (" ~ me.name ~ ") !", 10);
			print(" breaker broke=" ~ me.name ~ " load=" ~ me.load ~ " exceeds max amp=" ~ me.power);
			#fgcommand("play-audio-sample", props.Node.new(pocSound) );
			c150.PlaySound("breakers");
		}
	},
	isServiceable : func {
		return me.is_serviceable.getBoolValue();
	},
	reset : func {
		me.load = 0.0;
		me.is_serviceable.setBoolValue( 1 );
	},
};

var ElectricalCircuit =  {
	outputList : [],
	breakerList : {},
	breakerListKeys : [],
	addOutput : func(n) {
		append(me.outputList, n);
		debug_print("new electrical output : " ~ n.name ~ ", " ~ n.power ~ " Watt");
		if(n.breaker != nil and !contains(me.breakerList, n.breaker))
			print("    using unknown breaker : " ~ n.breaker);
		if(n.masterbreaker != nil and !contains(me.breakerList, n.masterbreaker))
			print("    using unknown master breaker : " ~ n.masterbreaker);
		if(n.switch != nil and props.globals.getNode(n.switch) == nil) {
			print("    using unknown switch : " ~ n.switch);
			props.globals.initNode(n.switch, 0, "BOOL");
		}
		if(n.masterswitch != nil ) {
			props.globals.initNode(n.masterswitch, 0, "BOOL");
		}
		props.globals.initNode(n.property, 0.0, "DOUBLE");
	},
	addBreaker : func(n) {
		me.breakerList[n.property] = n;
		setprop(n.property, 1);
		me.breakerListKeys = keys(me.breakerList);
		debug_print("new electrical breaker  : " ~ n.name ~ ", " ~ n.power ~ " Ampere");
	},
	getBreaker : func(n) {
		return me.breakerList[n];
	},
};


# list of circuit breakers

# jauge essence + inst lts + indicateur virage
ElectricalCircuit.addBreaker( Breaker.new(name:"FUEL IND + INST LTS breaker", power:3,
					  property:"/controls/circuit-breakers/instrument-lights") );

ElectricalCircuit.addBreaker( Breaker.new(name:"Radio 1 breaker", power:10,
					  property:"/controls/circuit-breakers/nav-com-1") );

ElectricalCircuit.addBreaker( Breaker.new(name:"Radio 2 breaker", power:5,
					  property:"/controls/circuit-breakers/nav-com-2") );

ElectricalCircuit.addBreaker( Breaker.new(name:"Radio 3 breaker", power:5,
					  property:"/controls/circuit-breakers/nav-com-3") );

# NAV + DOME + relais alt
ElectricalCircuit.addBreaker( Breaker.new(name:"NAV + DOME breaker", power:10,
					  property:"/controls/circuit-breakers/navigation-lights") );

ElectricalCircuit.addBreaker( Breaker.new(name:"PITOT HT + BCN breaker", power:20,
					  property:"/controls/circuit-breakers/beacon") );

ElectricalCircuit.addBreaker( Breaker.new(name:"STROBE breaker", power:10, # ?
property:"/controls/circuit-breakers/strobe") );

ElectricalCircuit.addBreaker( Breaker.new(name:"LDG LTS breaker", power:25,
					  property:"/controls/circuit-breakers/landing") );

ElectricalCircuit.addBreaker( Breaker.new(name:"FLAPS SLO/BLO breaker", power:15,
					  property:"/controls/circuit-breakers/flaps") );

ElectricalCircuit.addBreaker( Breaker.new(name:"Alternator breaker", power:15, # ?
property:"/controls/circuit-breakers/alternator") );


var masterBreaker = Breaker.new(name:"Master breaker", power:70,
				property:"/controls/circuit-breakers/master");

ElectricalCircuit.addBreaker( masterBreaker );



# list of outputs

ElectricalCircuit.addOutput( Output.new(name:"NAV LT", power:5.6, 
					property:"/systems/electrical/outputs/navigation-lights",
					switch:"controls/lighting/nav-lights",
						breaker:"/controls/circuit-breakers/navigation-lights") );

ElectricalCircuit.addOutput( Output.new(name:"DOME LT", power:0.3, 
					property:"/systems/electrical/outputs/dome-light",
					switch:"controls/lighting/dome-light",
						breaker:"/controls/circuit-breakers/navigation-lights") );

ElectricalCircuit.addOutput( Output.new(name:"BCN", power:7, 
					property:"/systems/electrical/outputs/beacon",
					switch:"sim/model/c150/lighting/beacon/state",
						breaker:"/controls/circuit-breakers/beacon") );

ElectricalCircuit.addOutput( Output.new(name:"PITOT HT", power:1, 
					property:"/systems/electrical/outputs/pitot-heat",
					switch:"controls/anti-ice/pitot-heat",
						breaker:"/controls/circuit-breakers/beacon") );

ElectricalCircuit.addOutput( Output.new(name:"Strobe Lights", power:3, 
					property:"/systems/electrical/outputs/strobe-lights",
					switch:"sim/model/c150/lighting/strobe/state",
						breaker:"/controls/circuit-breakers/strobe") );

ElectricalCircuit.addOutput( Output.new(name:"LDG LTS", power:15, 
					property:"/systems/electrical/outputs/landing-light",
					switch:"controls/lighting/landing-light",
						breaker:"/controls/circuit-breakers/landing") );

ElectricalCircuit.addOutput( Output.new(
					name:"Flaps", power:10, 
					property:"/systems/electrical/outputs/flaps",
					switch:"/controls/flight/flaps-cmd",
					breaker:"/controls/circuit-breakers/flaps")
);


setlistener("/instrumentation/nav[1]/power-btn", func( i ){
	if( getprop("/sim/model/c150/options/second-vhf") ){
		setprop("/instrumentation/nav[1]/power-btn-int", i.getValue() );
	}
}, 1);

# 1.5A receiving
# 6A transmitting
ElectricalCircuit.addOutput( Output.new(name:"Radio 1", power:1.25, # 2.5 / 2
					property:"/systems/electrical/outputs/nav[0]",
					switch:"instrumentation/nav[0]/power-btn",
						breaker:"/controls/circuit-breakers/nav-com-1") );

ElectricalCircuit.addOutput( Output.new(name:"Radio 1", power:1.25, # 2.5 / 2
					property:"/systems/electrical/outputs/comm[0]",
					switch:"instrumentation/nav[0]/power-btn",
						breaker:"/controls/circuit-breakers/nav-com-1") );

ElectricalCircuit.addOutput( Output.new(name:"Radio Nav 2", power:0.95, # 1.9 / 2
					property:"/systems/electrical/outputs/nav[1]",
					switch:"instrumentation/nav[1]/power-btn-int",
						breaker:"/controls/circuit-breakers/nav-com-2") );

ElectricalCircuit.addOutput( Output.new(name:"Radio Comm 2", power:0.95, # 1.9 / 2 
					property:"/systems/electrical/outputs/comm[1]",
					switch:"instrumentation/nav[1]/power-btn-int",
						breaker:"/controls/circuit-breakers/nav-com-2") );

ElectricalCircuit.addOutput( Output.new(name:"Transponder", power:1, 
					property:"/systems/electrical/outputs/transponder",
					switch:nil,
						breaker:"/controls/circuit-breakers/nav-com-3") );

ElectricalCircuit.addOutput( Output.new(name:"Carb Heat", power:1, 
					property:"/systems/electrical/outputs/carb-heat",
					switch:"controls/anti-ice/engine[0]/carb-heat",
						breaker:nil) );



ElectricalCircuit.addOutput( Output.new(name:"Turn Coordinator", power:0.8, 
					property:"/systems/electrical/outputs/turn-coordinator",
					switch:nil,
						breaker:nil) );

ElectricalCircuit.addOutput( Output.new(name:"Fuel Indicators", power:0.1, 
					property:"/systems/electrical/outputs/fuel-indicators",
					switch:nil,
					breaker:"/controls/circuit-breakers/instrument-lights") );

ElectricalCircuit.addOutput( Output.new(name:"Instrument Lights", power:1.1, 
					property:"/systems/electrical/outputs/instrument-lights",
					switch:nil,
						potar:"controls/lighting/instruments-norm",
					breaker:"/controls/circuit-breakers/instrument-lights") );

ElectricalCircuit.addOutput( Output.new(name:"Annunciator", power:1, 
					property:"/systems/electrical/outputs/annunciators",
					switch:nil,
						breaker:nil) );

ElectricalCircuit.addOutput( Output.new(name:"HSI", power:1, 
					property:"/systems/electrical/outputs/hsi",
					switch:nil,
						breaker:nil) );

ElectricalCircuit.addOutput( Output.new(name:"Audio Panel 1", power:1, 
					property:"/systems/electrical/outputs/audio-panel[0]",
					switch:nil,
						breaker:nil) );

ElectricalCircuit.addOutput( Output.new(name:"ADF", power:1, 
					property:"/systems/electrical/outputs/adf",
					switch: "/sim/model/c150/options/adf",
						breaker:nil) );

ElectricalCircuit.addOutput( 
	Output.new(
		name:"Starter", 
		power:100, 
		property:"/systems/electrical/outputs/starter[0]",
		switch:"/controls/engines/engine[0]/starter-cmd",
		breaker:nil,
		novbus:1
	) 
);


##
# This is the main electrical system update function.
#
var flp_md = flaps_mode.getBoolValue();
var stop_at = -1;

setlistener( flaps_mode, func{ flp_md = flaps_mode.getBoolValue(); } );

var update_electrical = func {
	var time = getprop("/sim/time/elapsed-sec");
	var dt = time - last_time;
	last_time = time;
	
	update_virtual_bus( dt );
	
	# Flaps
	var cmd = flaps_cmd.getIntValue();
	if( cmd == 0 or flaps_volts.getDoubleValue() < 8 ) {
		return;
	}
	if( flp_md == 0 ){
		# reset flaps_cmd when reaching a virtual detent
		if( ( cmd == 1 and flaps_pos.getDoubleValue() >= stop_at ) or ( cmd == -1 and flaps_pos.getDoubleValue() <= stop_at ) ){
			flaps_cmd.setIntValue( 0 );
			return;
		}
	}
	var speed_factor = flaps_motor.getDoubleValue();
	flaps_pos.setDoubleValue( math.clamp( flaps_pos.getDoubleValue() + cmd * speed_factor * dt, 0.0, 1.0 ) );
	if( flaps_pos.getDoubleValue() == 0.0 or flaps_pos.getDoubleValue() == 1.0 ){
		flaps_cmd.setIntValue( 0 );
	}
}

var electrical_timer = maketimer( 0.0, func() { update_electrical() } );
electrical_timer.simulatedTime = 1;

controls.flapsDown = func ( i ){
	flaps_cmd.setIntValue( i );
	var crt_pos = flaps_pos.getDoubleValue();
	if( i > 0 ){
		# Flaps Down
		if( crt_pos < 0.23 ) stop_at = 0.25;
		elsif( crt_pos < 0.47 ) stop_at = 0.5;
		elsif( crt_pos < 0.72 ) stop_at = 0.75;
		else stop_at = 1.0;
	} elsif( i < 0 ){
		# Flaps Up
		if( crt_pos > 0.78 ) stop_at = 0.75;
		elsif( crt_pos > 0.53 ) stop_at = 0.5;
		elsif( crt_pos > 0.28 ) stop_at = 0.25;
		else stop_at = 0.0;
	} else {
		stop_at = -1.0;
	}
}

##
# Initialize the electrical system
#

var init_electrical = func {
	
	battery = BatteryClass.new();
	alternator = AlternatorClass.new();
	
	setprop("/systems/electrical/power-source", "");
	
	# Request that the update function be called next frame
	electrical_timer.start();
	print("Electrical system initialized");
}

var reset_battery_and_circuit_breakers = func {
	# Charge battery to 100 %
	battery.reset_to_full_charge();
	
	# Reset circuit breakers
	foreach(var breaker; ElectricalCircuit.breakerListKeys) {
		ElectricalCircuit.getBreaker(breaker).reset();
	}
	
}

##
# Battery model class.
#

# Service Manual p.16-2: battery is 12V, 25Ah

var BatteryClass = {};

BatteryClass.new = func {
	var obj = { parents : [BatteryClass],
		ideal_volts : 12.0,
		ideal_amps : 60.0,
		amp_hours : 25.0,
		charge_percent : getprop("/systems/electrical/battery-charge-percent") or 100.0,
		charge_amps : 7.0,
		low_battery_warn : 0,
	};
	setprop("/systems/electrical/battery-charge-percent", obj.charge_percent);
	return obj;
}

##
# Passing in positive amps means the battery will be discharged.
# Negative amps indicates a battery charge.
#

BatteryClass.apply_load = func (amps, dt) {
	var old_charge_percent = me.charge_percent;
	
	if (getprop("/sim/freeze/replay-state"))
		return me.amp_hours * old_charge_percent;
	
	var amphrs_used = amps * dt / 3600.0;
	var percent_used = amphrs_used / me.amp_hours * 100.0;
	
	var new_charge_percent = std.max(0.0, std.min(old_charge_percent - percent_used, 100.0));
	
	if (new_charge_percent < 40.0 and me.low_battery_warn == 0) {
		# only one warning per session, but also warn on startup
		me.low_battery_warn = 1;
		gui.popupTip("Warning: Low battery! Enable alternator or apply external power to recharge battery!", 10);
	}
	me.charge_percent = new_charge_percent;
	setprop("/systems/electrical/battery-charge-percent", new_charge_percent);
	return me.amp_hours * new_charge_percent;
}

##
# Return output volts based on percent charged.  Currently based on a simple
# polynomial percent charge vs. volts function.
#

BatteryClass.get_output_volts = func {
	var x = 1.0 - ( me.charge_percent / 100 );
	var tmp = -(3.0 * x - 1.0);
	var factor = (tmp*tmp*tmp*tmp*tmp + 32) / 32;
	return me.ideal_volts * factor;
}


##
# Return output amps available.  This function is totally wrong and should be
# fixed at some point with a more sensible function based on charge percent.
# There is probably some physical limits to the number of instantaneous amps
# a battery can produce (cold cranking amps?)
#

BatteryClass.get_output_amps = func {
	var x = 1.0 - ( me.charge_percent / 100 );
	var tmp = -(3.0 * x - 1.0);
	var factor = (tmp*tmp*tmp*tmp*tmp + 32) / 32;
	return me.ideal_amps * factor;
}

##
# Set the current charge instantly to 100 %.
#

BatteryClass.reset_to_full_charge = func {
	print("reset_to_full_charge before = ", me.charge_percent, "%");
	me.apply_load(-(100.0 - me.charge_percent) * me.amp_hours, 3600);
	print("reset_to_full_charge after = ", me.charge_percent, "%");
}

##
# Alternator model class.
#

# Service Manual p.16-6: alternator is rated at 14V, 60A

var AlternatorClass = {};

AlternatorClass.new = func {
	var obj = { parents : [AlternatorClass],
		rpm_source : props.globals.getNode( "engines/engine[0]/rpm", 1 ),
		rpm_threshold : 700.0,
		ideal_volts : 14.2,
		ideal_amps : 60.0 };
	obj.rpm_source.setDoubleValue( 0.0 );
	return obj;
}

##
# Computes available amps and returns remaining amps after load is applied
#

AlternatorClass.apply_load = func( amps, dt ) {
	# Scale alternator output for rpms < 800.  For rpms >= 800
	# give full output.  This is just a WAG, and probably not how
	# it really works but I'm keeping things "simple" to start.
	var factor = me.rpm_source.getDoubleValue() / me.rpm_threshold;
	if ( factor > 1.0 ) {
		factor = 1.0;
	}
	# print( "alternator amps = ", me.ideal_amps * factor );
	var available_amps = me.ideal_amps * factor;
	return available_amps - amps;
}

##
# Return output volts based on rpm
#

AlternatorClass.get_output_volts = func {
	# scale alternator output for rpms < 800.  For rpms >= 800
	# give full output.  This is just a WAG, and probably not how
	# it really works but I'm keeping things "simple" to start.
	var factor = me.rpm_source.getDoubleValue() / me.rpm_threshold;
	if ( factor > 1.0 ) {
		factor = 1.0;
	}
	# print( "alternator volts = ", me.ideal_volts * factor );
	return me.ideal_volts * factor;
}


##
# Return output amps available based on rpm.
#

AlternatorClass.get_output_amps = func {
	# scale alternator output for rpms < 800.  For rpms >= 800
	# give full output.  This is just a WAG, and probably not how
	# it really works but I'm keeping things "simple" to start.
	var factor = me.rpm_source.getDoubleValue() / me.rpm_threshold;
	if ( factor > 1.0 ) {
		factor = 1.0;
	}
	# print( "alternator amps = ", ideal_amps * factor );
	return me.ideal_amps * factor;
}

##
# Model the system of relays and connections that join the battery,
# alternator, starter, master/alt switches, external power supply.
#

var update_virtual_bus = func( dt ) {
	var serviceable = getprop("/systems/electrical/serviceable");
	var external_volts = 0.0;
	var load = 0.0;
	var battery_volts = 0.0;
	var alternator_volts = 0.0;
	if ( serviceable ) {
		battery_volts = battery.get_output_volts();
		alternator_volts = alternator.get_output_volts();
	}
	
	# switch state
	var master_bat = batSwN.getValue();
	var master_alt = altSwN.getValue();
	if (getprop("/controls/electric/external-power"))
	{
		external_volts = 14.2;
	}
	
	# determine power source
	var bus_volts = 0.0;
	var power_source = "";
	if ( master_bat ) {
		bus_volts = battery_volts;
		power_source = "battery";
	}
	if ( master_alt and (alternator_volts > bus_volts) ) {
		bus_volts = alternator_volts;
		power_source = "alternator";
	}
	if ( external_volts > bus_volts ) {
		bus_volts = external_volts;
		power_source = "external";
	}
	#print( "virtual bus volts = ", bus_volts );
	
	# bus network (1. these must be called in the right order, 2. the
	# bus routine itself determins where it draws power from.)
	load += electrical_bus_1();
	
	# system loads and ammeter gauge
	var ammeter = 0.0;
	if ( bus_volts > 1.0 ) {
		# ammeter gauge
		if ( power_source == "battery" ) {
			ammeter = -load;
		} else {
			ammeter = battery.charge_amps;
		}
	}
	# print( "ammeter = ", ammeter );
	
	var overvoltage_test = 0;
	
	# charge/discharge the battery
	if ( power_source == "battery" ) {
		battery.apply_load( load, dt );
		overvoltage_test = 1;
	} elsif ( bus_volts > battery_volts ) {
		battery.apply_load( -battery.charge_amps, dt );
	}
	
	overvoltage_light.setDoubleValue( bus_volts * overvoltage_test );
	
	# filter ammeter needle pos
	ammeter_ave = 0.8 * ammeter_ave + 0.2 * ammeter;
	
	# outputs
	setprop("/systems/electrical/amps", ammeter_ave);
	setprop("/systems/electrical/volts", bus_volts);
	setprop("/systems/electrical/battery-volts", battery_volts);
	setprop("/systems/electrical/alternator-volts", alternator_volts);
	setprop("/systems/electrical/power-source", power_source);
	if (bus_volts > 9)
		vbus_volts = bus_volts;
	else
		vbus_volts = 0.0;
	
	return load;
}


var electrical_bus_1 = func() {
	var bus_volts = 0.0;
	var load = 0.0;
	
	# check master breaker
	if ( masterBreaker.isServiceable() ) {
		# we are feed from the virtual bus
		bus_volts = vbus_volts;        
	}
	#print("Bus volts: ", bus_volts);
	
	# initialize load
	foreach(var breaker; ElectricalCircuit.breakerListKeys) {
		ElectricalCircuit.getBreaker(breaker).load = 0;
	}
	
	foreach(var output; ElectricalCircuit.outputList) {
		var output_volts = bus_volts;
		#        print("output:" ~ output.name ~ " breaker=" ~ (output.breaker == nil ? "nil" : output.breaker) ~ 
		#            " masterswitch=" ~ (output.masterswitch == nil ? "nil" : output.masterswitch));
		
		if( output.switch != nil and getprop(output.switch) == 0 )
			output_volts = 0.0;
		if( output.masterswitch != nil and getprop(output.masterswitch) <= 0 )
			output_volts = 0.0;
		if( output.breaker != nil and !ElectricalCircuit.getBreaker(output.breaker).isServiceable() )
			output_volts = 0.0;
		if( output.masterbreaker != nil and !ElectricalCircuit.getBreaker(output.masterbreaker).isServiceable() )
			output_volts = 0.0;
		if( output.potar != nil ) {
			output_volts = output_volts * getprop(output.potar);
			setprop(output.property ~ "-norm", output_volts / 12.0);
		}
		var thisload = output.power * output_volts / 12.0;
		if( ! output.novbus)
			masterBreaker.applyLoad( thisload );
		
		if( output.breaker != nil) {
			ElectricalCircuit.getBreaker(output.breaker).applyLoad( thisload );
		}
		if( output.masterbreaker != nil ) {
			ElectricalCircuit.getBreaker(output.masterbreaker).applyLoad( thisload );
		}
		
		load += thisload;
		setprop(output.property, output_volts);
	}
	
	
	# Instrument Power: ignition, fuel, oil temperature
	if ( getprop("/controls/circuit-breakers/instr") ) {
		setprop("/systems/electrical/outputs/instr-ignition-switch", bus_volts);
	} else {
		setprop("/systems/electrical/outputs/instr-ignition-switch", 0.0);
	}
	
	
	
	# Turn Coordinator and directional gyro Power
	if ( getprop("/controls/circuit-breakers/turn-coordinator") ) {
		setprop("/systems/electrical/outputs/DG", bus_volts);
		load += bus_volts / 14;
	} else {
		setprop("/systems/electrical/outputs/DG", 0.0);
	}
	
	# register bus voltage
	ebus1_volts = bus_volts;
	
	# return cumulative load
	return load;
}
