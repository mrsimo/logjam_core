function logjam_graph_app_data(appCallers) {

  var r1 = 800 / 2,
      r0 = r1 - 120,
      w = 1400,
      h = w,
      cw = 700,
      ch = 420;

  var fill = d3.scale.category20c();

  var chord = d3.layout.chord()
        .padding(.02)
        .sortSubgroups(d3.descending)
        .sortChords(d3.descending);

  var arc = d3.svg.arc()
        .innerRadius(r0)
        .outerRadius(r0 + 20);

  var svg = d3.select("#call-graph-display").append("svg:svg")
        .attr("width", w)
        .attr("height", h)
        .append("svg:g")
        .attr("transform", "translate(" + cw + "," + ch + ")");

  // Initialize the info display.
  var info = d3.select("#call-graph-info");

  var indexByName = {},
      nameByIndex = {},
      appNames = d3.set(),
      n = 0;

  var scale =  d3.scale.log().domain(d3.extent(appCallers, function(d){ return d.count;}));

  function appName(name) {
    return name;
  }

  appCallers.forEach(function(app) {
    appNames.add(app.source);
    appNames.add(app.target);
  });
  appNames.values().sort().forEach(function(name) {
    name = appName(name);
    if (!(name in indexByName)) {
      nameByIndex[n] = name;
      indexByName[name] = n++;
    }
  });

  var matrix = [], scaled_matrix = [];
  for (var i = 0; i < n; i++) {
    matrix[i] = [];
    scaled_matrix[i] = [];
    for (var j = 0; j < n; j++) {
      matrix[i][j] = 0;
      scaled_matrix[i][j] = 0;
    }
  }
  appCallers.forEach(function(d) {
    var source = indexByName[appName(d.target)],
        row = matrix[source],
        scaled_row = scaled_matrix[source],
        index = indexByName[appName(d.source)];
    if (!row) {
      row = matrix[source] = [];
      for (var i = -1; ++i < n;) row[i] = 0;
    }
    row[index] = d.count;
    if (!scaled_row) {
      scaled_row = scaled_matrix[source] = [];
      for (var j = -1; ++j < n;) scaled_row[j] = 0;
    }
    scaled_row[index] = scale(d.count);
  });

  function call_info_text(d) {
    var ti = d.target.index,
        si = d.source.index,
        caller = nameByIndex[ti],
        callee = nameByIndex[si],
        n = matrix[si][d.source.subindex],
        m = matrix[ti][d.target.subindex];

    var text = caller + " called " + callee + " " + formatter(n) + " times.";
    if (m>0) {
      text += "</br>" + callee + " called " + caller + " " + formatter(m) + " times.";
    }
    return text;
  }

  chord.matrix(scaled_matrix);

  var g = svg.selectAll("g.group")
        .data(chord.groups)
        .enter().append("svg:g")
        .attr("class", "group");

  g.append("svg:path")
    .style("fill", function(d) { return fill(d.index); })
    .style("stroke", function(d) { return fill(d.index); })
    .attr("d", arc)
    .on("mouseover", function(g, i) {
      svg.selectAll("path.chord")
        .classed("active", function(d) { return d.source.index == i || d.target.index == i; });
    })
    .on("mouseout", function(d) {
      // leave the arc selection, hard to read otherwise: svg.selectAll(".active").classed("active", false);
    });

  g.append("svg:text")
    .each(function(d) { d.angle = (d.startAngle + d.endAngle) / 2; })
    .attr("dy", ".35em")
    .attr("fill", function(d) { return d.value == 0 ? "green" : "black" ;})
    .attr("text-anchor", function(d) { return d.angle > Math.PI ? "end" : null; })
    .attr("transform", function(d) {
      return "rotate(" + (d.angle * 180 / Math.PI - 90) + ")"
        + "translate(" + (r0 + 45) + ")"
        + (d.angle > Math.PI ? "rotate(180)" : "");
    })
    .text(function(d) { return nameByIndex[d.index]; })
    .on("mouseover", function(g, i) {
      svg.selectAll("path.chord")
        .classed("active", function(d) { return d.source.index == i || d.target.index == i; });
    })
    .on("mouseout", function(d) {
      // leave the arc selection, hard to read otherwise: svg.selectAll(".active").classed("active", false);
    });

  var formatter = d3.format(",.0f");

  svg.selectAll("path.chord")
    .data(chord.chords)
    .enter().append("svg:path")
    .attr("class", "chord")
    .style("stroke", function(d) { return d3.rgb(fill(d.source.index)).darker(); })
    .style("fill", function(d) { return fill(d.source.index); })
    .attr("d", d3.svg.chord().radius(r0))
    .on("mouseover", function(d) {
      svg.selectAll(".active").classed("active", false);
      // using :hover now instead of:  svg.selectAll("path.chord").classed("active", function(p) { return p === d; });
      info.html(call_info_text(d));
    })
    .on("mouseout", function(d) {
      svg.selectAll(".active").classed("active", false);
      info.text("");
    });

  // Returns an event handler for fading a given chord group.
  function fade(opacity) {
    return function(g, i) {
      svg.selectAll("path.chord")
        .filter(function(d) { return d.source.index != i && d.target.index != i; })
        .transition()
        .style("opacity", opacity);
    };
  }
}

function logjam_load_graph_data(group, json_urls) {
  d3.selectAll("svg").remove();
  $("#spinner").show();
  d3.json(json_urls[group], function(error, appCallers) {
    logjam_graph_app_data(appCallers);
    $("#spinner").hide();
  });
}