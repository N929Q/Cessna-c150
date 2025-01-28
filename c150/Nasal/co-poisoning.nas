#	Carbon Monoxide (CO) Poisoning Simulation
#	by Bea Wolf (D-ECHO) 2021 
#	for the Cessna 150

#	References:
#		1	https://www.faa.gov/documentLibrary/media/Advisory_Circular/AC_20-32B.pdf
#		2	https://skybrary.aero/index.php/Carbon_Monoxide_Poisoning
#		3	https://www.aircraftspruce.com/catalog/pspages/asaCO.php
#		4	https://en.wikipedia.org/wiki/Carbon_monoxide_poisoning#Signs_and_symptoms
#		5	https://www.medizin-netz.de/umfassende-berichte/vergiftungen-mit-kohlenmonoxid-co/
#		6	https://de.wikipedia.org/wiki/Kohlenstoffmonoxid#Toxizit%C3%A4t
#		7	https://www.avweb.com/ownership/heater-checkout/
#		8	https://www.instrumart.com/assets/COintheCockpit.pdf

#	Master:		CO Poisoning needs to be enabled using the GUI:
#		/sim/co-poisoning/enabled

#	Chance:		CO Poisoning is very unlikely. We don't simulate the probability based on engine time etc., 
#			but rather use a general chance set by
#		/sim/co-poisoning/chance
#			This is the chance for a leak between the cabin heating system and the exhaust system.
#			When this leak occurs, CO rate will be determined by a random "leak size" factor (0.1 - 100)
#			multiplied by the amount of cabin heat applied and a constant
#			This constant is set so that an average leak (size 1.0) at full cabin heat (1.0) leads to a
#			rate of 1 ppm per sec (unconsciousness level at 1600 ppm reached after about 27 min)
#			TODO Implement: ref. 8, p.13: Amount of CO getting into the cabin is highest at mixture settings rich of peak EGT

#	Symptoms:	We determine the effects based on the the amount of CO in the cabin air (see table ref. 3 and 4)
#			and length of exposure. To facilitate this, a "harm" value is set by multiplying
#		/sim/co-poisoning/co-air-ppm (parts per million)
#			with the time of exposure, translated into blood CO percentage (CO-Hb, the amount of Hb occupied by CO)
#		/sim/co-poisoning/co-hb-pct
#			ref. 5: 
#				breathing normal air, CO-Hb reduces by 50% every 240 min
#				700 ppm translates to 50% CO-Hb
#			ref. 4: at 3200 bpm, death in ~ 30 min
#					-> assume: 1600 ppm*h equals to 50% CO-Hb
#			TODO Implement: ref. 8, p. 11 (diagram)

#	Procedure (ref. 2):
#			* Shut off cabin heat: This stops the CO level from increasing
#			* Increase ventilation (cabin air, windows, doors on the ground):
#				This decreases the CO level in the cabin air up to 0

#	Ending:		The mentioned leak can only be reset using the GUI (disable master or click "reset leak")

#	Set up properties

var base_property	=	props.globals.initNode( "/sim/co-poisoning" );

var check_or_create = func ( rel_path, value, type ) {
	if( getprop( rel_path ) != nil ){
		return base_property.getNode( rel_path );
	} else {
		return base_property.initNode( rel_path, value, type );
	}
}

var master		=	check_or_create( "master", 0, "BOOL" );
var chance		=	check_or_create( "chance", 0.01, "DOUBLE" );
var ppm			=	base_property.initNode( "co-air-ppm", 0.0, "DOUBLE" );
var co_hb		=	base_property.initNode( "co-hb-pct", 0.0, "DOUBLE" );

var eng_running		=	props.globals.getNode( "/engines/engine[0]/running", 1 );
var cabin_heat		=	props.globals.getNode( "/environment/aircraft-effects/cabin-heat-set", 1 );
var cabin_air		=	props.globals.getNode( "/environment/aircraft-effects/cabin-air-set", 1 );
var doors = [
		props.globals.getNode( "sim/model/c150/doors/door[0]/position-norm", 1 ),
		props.globals.getNode( "sim/model/c150/doors/door[1]/position-norm", 1 ),
];
var windows = [
		props.globals.getNode( "sim/model/c150/doors/window[0]/position-norm", 1 ),
		props.globals.getNode( "sim/model/c150/doors/window[1]/position-norm", 1 ),
];

var elapsed_sec		=	props.globals.getNode( "/sim/time/elapsed-sec", 1 );

#	Set up variables

var co_poisoning_enabled = 0;
var leak_existing = 0;
var leak_size = 0.0;
var chance_var = chance.getDoubleValue();
var cabin_air_factor = 0.1;
var window_factor = 0.4;
var door_factor = 1.0;
var last_elapsed_sec = elapsed_sec.getDoubleValue();
var last_message_sec = 0.0;


var chance_loop = func () {
	if( rand() <= chance_var ){
		#	Leak exists
		leak_existing = 1;
		leak_size = 0.1 + rand() * 99.9;
		screen.log.write( "Leak exists, CO poisoning is occuring!. Leak size (0.5-1.5): "~ sprintf("%3.2f", leak_size ) );
		chance_loop_timer.stop();
	}
}
var chance_loop_timer = maketimer( 60, chance_loop );
chance_loop_timer.simulatedTime = 1;

var co_loop = func () {
	var time_diff = elapsed_sec.getDoubleValue() - last_elapsed_sec;
	last_elapsed_sec = elapsed_sec.getDoubleValue();
	
	var co_rate = eng_running.getBoolValue() * cabin_heat.getDoubleValue() * leak_size 
			- ( cabin_air.getDoubleValue() * cabin_air_factor 
				+ ( windows[0].getDoubleValue() + windows[1].getDoubleValue() ) * window_factor
				+ ( doors[0].getDoubleValue() + doors[1].getDoubleValue() ) * door_factor );
			
	#screen.log.write( "CO Rate: "~ co_rate ); Debug
	
	var new_ppm = ppm.getDoubleValue() + co_rate * time_diff;
	
	ppm.setDoubleValue( new_ppm );
	
	var current_cohb = co_hb.getDoubleValue();
	
	#	Reduce CO-Hb due to breathing normal air
	if( new_ppm < 50 ){
		current_cohb -= ( 0.5 * ( time_diff / 14400 ) * current_cohb );
	}
	
	#	Increase CO-Hb due to exposition to elevated CO air level
	#	1600 ppm*h ~ 50% CO-Hb
	current_cohb += ( new_ppm * ( time_diff / 3600 ) ) / 32;
	
	co_hb.setDoubleValue( current_cohb );
	
	# Symptoms part (ref. 2)
	if( ( last_message_sec - last_elapsed_sec ) / 60 ){
		last_message_sec = last_elapsed_sec;
		if( current_cohb > 50 ){
			screen.log.write( "Unconscious" );
		} elsif( current_cohb > 40 ){
			screen.log.write( "It's really hard to stay awake." );
		} elsif( current_cohb > 30 ){
			screen.log.write( "My head hurts and it's getting difficult to breathe!" );
		} elsif( current_cohb > 20 ){
			screen.log.write( "I'm feeling dizzy, everything's turning!" );
		} elsif( current_cohb > 10 ){
			screen.log.write( "I'm feeling kind of unwell." );
		} else {
			last_message_sec = 0;
		}
	}
		
}

var co_loop_timer = maketimer( 20, co_loop );
co_loop_timer.simulatedTime = 1;

var check_master = func {
	if( master.getBoolValue() and !co_poisoning_enabled ){
		screen.log.write( "CAUTION: CO-Poisoning Simulation is enabled!" );
		co_poisoning_enabled = 1;
		chance_loop_timer.start();
		co_loop_timer.start();
		last_elapsed_sec = elapsed_sec.getDoubleValue();
	} elsif( !master.getBoolValue() and co_poisoning_enabled ){
		co_poisoning_enabled = 0;
		chance_loop_timer.stop();
		co_loop_timer.stop();
		if( leak_existing ){
			leak_existing = 0;
			ppm.setDoubleValue( 0.0 );
			co_hb.setDoubleValue( 0.0 );
		}
	}
}

setlistener( master, func { check_master(); } );

setlistener( "/sim/signals/fdm-initialized", func { check_master(); } );

setlistener( chance, func {
	chance_var = chance.getDoubleValue();
});

#	GUI API
var reset_co_leak = func {
	if( leak_existing ){
		leak_existing = 0;
		leak_size = 0;
		if( !chance_loop_timer.isRunning ){	chance_loop_timer.start();	}
	}
}

