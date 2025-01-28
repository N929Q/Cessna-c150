#####
#	Cessna 150 Family Nasal
#####

## Livery Selection
aircraft.livery.init("Aircraft/c150/Models/Liveries/");

#	Global Variables
var debug_mode	=	0;

#	Properties
var debug_prop	=	props.globals.getNode("/c150/debug-mode", 1);
var rpmN	=	props.globals.getNode("engines/engine[0]/rpm", 1);
var voltN	=	props.globals.getNode("/systems/electrical/volts", 1);
var hmHobbs	=	props.globals.getNode("instrumentation/clock/hobbs-meter/sec", 1);
var hmTach	=	props.globals.getNode("instrumentation/clock/tach-meter/sec", 1);

#	Debug Mode
setlistener( debug_prop, func {
	debug_mode = debug_prop.getBoolValue();
});
var debug_print = func ( text ){
	if( debug_mode ){
		print( text );
	}
}

#	GUI Options
setlistener("/sim/model/c150/options/adf", func( i ){
	if( !i.getBoolValue() ){
		setprop("/instrumentation/adf/serviceable", 0);
	} else {
		setprop("/instrumentation/adf/serviceable", 1);
	}
});
setlistener("/sim/model/c150/options/second-vhf", func( i ){
	if( !i.getBoolValue() ){
		setprop("/instrumentation/comm[1]/serviceable", 0);
		setprop("/instrumentation/nav[1]/serviceable", 0);
	} else {
		setprop("/instrumentation/comm[1]/serviceable", 1);
		setprop("/instrumentation/nav[1]/serviceable", 1);
	}
});

#	Aircraft Lights
aircraft.light.new("/sim/model/c150/lighting/strobe", [0.05, 0.90], "controls/lighting/strobe" );
aircraft.light.new("/sim/model/c150/lighting/beacon", [0.40, 0.50], "controls/lighting/beacon" );

#	Aircraft Controls
var old_stepMagnetos = controls.stepMagnetos;
controls.stepMagnetos = func(change) {
	var new_value = getprop("controls/engines/engine/c150-magnetos") + change;
	if( new_value >= 0 and new_value <= 3)
		setprop("controls/engines/engine/c150-magnetos", new_value);
	old_stepMagnetos(change);
}

var old_applyParkingBrake = controls.applyParkingBrake;
controls.applyParkingBrake = func(change) {
	var brake = old_applyParkingBrake(change);
	if (!change) { return; }
	gui.popupTip("Brakes " ~ ['OFF', 'ON'][brake]);
}

#	Aircraft Functions

var calcDigits = func( v, prop, ndigit ) {
	v = int( v );
	for( var i = 0; i < ndigit ; i=i+1 ) {
		v2 = int( v / 10 );
		r = v - v2 * 10;
		setprop( prop~i, r );
		v = v2;
	}
}

var calcHoursMeter = func(dt) {
	if( rpmN.getValue() > 100.0 ) {
		hmHobbs.setValue( hmHobbs.getValue() + dt );
	}
	var q = hmTach.getValue() + dt * rpmN.getValue() / 2566.0;
	hmTach.setValue( q );
}

var setAdfFrequency = func(digit, n, m) {
	var v = getprop("instrumentation/adf[0]/frequencies/selected-khz-digits" ~ digit);
	if( digit == 2) {
		v = v + 10 * getprop("instrumentation/adf[0]/frequencies/selected-khz-digits3");
		setprop("instrumentation/adf[0]/frequencies/selected-khz-digits3", 0);
	}
	v = math.mod(v + n + m, m);
	setprop("instrumentation/adf[0]/frequencies/selected-khz-digits" ~ digit, v);
	var newFreq = getprop("instrumentation/adf[0]/frequencies/selected-khz-digits0") +
	10*getprop("instrumentation/adf[0]/frequencies/selected-khz-digits1") + 
	100*getprop("instrumentation/adf[0]/frequencies/selected-khz-digits2") + 
	1000*getprop("instrumentation/adf[0]/frequencies/selected-khz-digits3");
	if( newFreq >= 200 and newFreq <= 1800) {
		setprop("instrumentation/adf[0]/frequencies/selected-khz", newFreq);
	}
}

##########################################
# Click Sounds
##########################################

var PlaySound = func (name, timeout=0.1, delay=0) {
	var sound_prop = "/sim/model/c150/sound/" ~ name;
	
	settimer(func {
		# Play the sound
		setprop(sound_prop, 1);
		
		# Reset the property after 0.2 seconds so that the sound can be
		# played again.
		settimer(func {
			setprop(sound_prop, 0);
		}, timeout);
	}, delay);
};


var MainSystem = {
	parents: [Updatable],
	
	reset: func {
		
	},
	update: func(dt) {
		
		calcHoursMeter( dt );
		
		calcDigits( getprop("instrumentation/adf[0]/frequencies/selected-khz"), 
			    "instrumentation/adf[0]/frequencies/selected-khz-digits", 4);
	},
};

var dialog_battery_reload = func {
	reset_battery_and_circuit_breakers();
	gui.popupTip("The battery is now fully charged!");
}

print("Cessna 150 initializing...");

var loop = UpdateLoop.new(components: [MainSystem], update_period: 0.1, enable: 1);

var done_once = 0;
setlistener("/sim/signals/fdm-initialized", func {
	print("FDM is initialized...");
	
	if( getprop("/sim/aircraft-state") == "take-off" ){
		autostart_engine();
	}
	
	if( ! done_once ) {
		settimer(init_electrical, 1.0);
	}
	done_once = 1;
});

var autostart_engine = func{
	controls.startEngine(1);
	settimer(func {controls.startEngine(0);}, 5.0);
}

setlistener("/sim/aircraft-state", func( i ){
	if( i.getValue() == "take-off" ){
		autostart_engine();
	}
});

###############################################
# Cabin Environment, adapted from c172p
###############################################

var cabin_temp_degc = props.globals.getNode("/fdm/jsbsim/heat/cabin-air-temp-degc", 1);
var cabin_temp_state = 0;
var cabin_temp_msg = [
	[ 1, 0, 0, "It's freezing in here!"			],
	[ 1, 0, 0, "The cabin temperature's very cold!"	],
	[ 1, 1, 0, "I'm a bit cold in here"			],
	[ 0, 1, 0, "I feel comfortably warm",		],
	[ 1, 1, 0, "It's getting a bit hot",		],
	[ 1, 0, 0, "I feel like it's burning!"		],
];
var cabin_temp_iterations = 0;	# number of iterations without printing

var log_cabin_temp = func {
	var old_state = cabin_temp_state;
	var temp_degc = cabin_temp_degc.getDoubleValue();
	if( temp_degc < -15 ){
		cabin_temp_state = 0;
	} elsif ( temp_degc < 0 ){ 
		cabin_temp_state = 1;
	} elsif ( temp_degc < 15 ){
		cabin_temp_state = 2;
	} elsif ( temp_degc < 28 ){
		cabin_temp_state = 3;
	} elsif ( temp_degc < 40 ){
		cabin_temp_state = 4;
	} elsif ( cabin_temp_state != 5 ){
		cabin_temp_state = 5;
	}
	
	if( old_state != cabin_temp_state){
		screen.log.write( cabin_temp_msg[ cabin_temp_state ][3], cabin_temp_msg[ cabin_temp_state ][0], cabin_temp_msg[ cabin_temp_state ][1], cabin_temp_msg[ cabin_temp_state ][2] );
	} else {
		cabin_temp_iterations += 1;
		if( cabin_temp_iterations > 10 and cabin_temp_state != 3 ){
			cabin_temp_state = -1;
		}
	}
}
var cabin_temp_timer = maketimer(5.0, log_cabin_temp);
cabin_temp_timer.simulatedTime = 1;
cabin_temp_timer.start();
