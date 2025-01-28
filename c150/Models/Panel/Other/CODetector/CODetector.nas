#	Canvas CO Detector
#		This dynamically sets the date opened to be the current days minus about 3 months
#		and changes the indicator spot color when an elevated CO level is present

#	Properties
var co_air_ppm	= props.globals.getNode( "/sim/co-poisoning/co-air-ppm", 1 );
var date	= [
	props.globals.getNode( "/sim/time/utc/day",   1 ),
	props.globals.getNode( "/sim/time/utc/month", 1 ),
	props.globals.getNode( "/sim/time/utc/year",  1 ),
];

#	Canvas Set-Up
var co_canvas = canvas.new( {
	"name":	"CO Detector",
	"size": [512, 512],
	"view": [512, 512],
	"mipmapping": 1,
});

co_canvas.addPlacement( {"node": "Detector"} );
co_canvas.setColorBackground( 1, 1, 1, 1 );

var main_group = co_canvas.createGroup();

# SVG Font Mapper
var font_mapper = func(family, weight) {
	# print( "Family: "~ family ~", Weight: "~ weight );	# Debug output
	if( weight == "bold" ){
		return "LiberationFonts/LiberationSans-Bold.ttf";
	} else {
		return "LiberationFonts/LiberationSans-Regular.ttf";
	}
};


canvas.parsesvg( main_group, "Aircraft/c150/Models/Panel/Other/CODetector/CODetector.svg", {'font-mapper': font_mapper});

var setDate = func {
	var currentDate = [ 
		date[0].getValue(),
		date[1].getValue(),
		date[2].getValue(),
	];
	currentDate[ 0 ] = math.max( currentDate[0] - math.round( 6 * rand() ), 0 );
	currentDate[ 1 ] = math.max( currentDate[1] - 4 + math.round( 2 * rand() ), 0 );
	
	main_group.getElementById( "dateOpened" ).setText( currentDate[0] ~ "."~ currentDate[1] ~ "." ~ currentDate[2] );
}

var dateListener = setlistener( date[0], func {
	if( date[0] != nil ){
		setDate();
		removelistener( dateListener );
	}
});

var setIndicatorColor = func {
	var ppm = co_air_ppm.getDoubleValue();
	
	#	Brightness ( 0.3 - 1.0 )
	var brightness = math.clamp( 1 - ( ppm / 100 ), 0.3, 1.0 );
	
	main_group.getElementById( "indicatorSpot" ).setColorFill( 0.867 * brightness, 0.8 * brightness, 0.527 * brightness );
}

setlistener( co_air_ppm, func{ setIndicatorColor() } );
