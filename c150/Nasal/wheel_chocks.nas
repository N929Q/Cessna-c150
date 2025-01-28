#following ground equipement stuff placing was only possible by the help of the work by: Melchior Franz, Anders Gidenstam, Detelf Faber, onox. Thanks!
#wheel chocks======================================================

var chocks_enable = [
	props.globals.getNode("/sim/model/c150/chocks/left-enable"),
	props.globals.getNode("/sim/model/c150/chocks/right-enable"),
];

var chocks_models = [];

var chocks_pos = [
	[  1.2, -1.15 ],
	[  1.2,  1.15 ],
];

foreach( var el; chocks_enable ){
	append( chocks_models, {
		index: 0,
		add: func( x ) {
			var manager = props.globals.getNode("/models", 1);
			var i = 0;
			for (; 1; i += 1)
				if (manager.getChild("model", i, 0) == nil)
				break;
			
			var pos = geo.aircraft_position();
			pos.apply_course_distance( getprop("/orientation/heading-deg") + 180, chocks_pos[x][0] );
			pos.apply_course_distance( getprop("/orientation/heading-deg") + 90, chocks_pos[x][1] );
			pos.set_alt(props.globals.getNode("/position/ground-elev-m").getValue());

			geo.put_model("Aircraft/c150/Models/Ground/chocks/chocks.xml", pos,props.globals.getNode("/orientation/heading-deg").getValue());
			me.index = i;
		},
		remove:   func {
			props.globals.getNode("/models", 1).removeChild("model", me.index);
		},
	});
}
setlistener( chocks_enable[0], func( n ){
	if( n.getBoolValue() ){
		chocks_models[0].add(0);
	} else {
		chocks_models[0].remove();
	}
});
setlistener( chocks_enable[1], func( n ){
	if( n.getBoolValue() ){
		chocks_models[1].add(1);
	} else {
		chocks_models[1].remove();
	}
});
