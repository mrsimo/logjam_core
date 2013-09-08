function logjam_page_pie(params) {
  var data = params.data,
      legend = params.legend;

  /* Sizing and scales. */
  var w = params.w,
      h = params.h,
      r = w / 2,
      s = d3.sum(data),
      a = d3.scale.linear([0, s]).range([0, 2 * Math.PI]);

  /* The root panel. */
  var vis = d3.select(params.parent).append("svg")
        .data([data])
        .attr("width", w+400)
        .attr("height", h);

  function goto_page(page) {
    if (page != "Others...") {
      $('#page-field').val(page);
      $('#filter-form').submit();
    }
  }

  var cursorf = function(d,i){ return legend[i] != "Others..." ? "pointer" : "arrow"; };

  var
  color = d3.scale.category20(),
  donut = d3.layout.pie(),
  arc = d3.svg.arc().innerRadius(0).outerRadius(r);

  var arcs = vis.selectAll("g.arc")
        .data(donut)
        .enter().append("g")
        .attr("class", "arc")
        .style("font", "10px sans-serif")
        .attr("transform", "translate(" + r + "," + r + ")");

  arcs.append("path")
    .style("cursor", cursorf)
    .on("click", function(d,i){ goto_page(legend[i]); })
    .attr("fill", function(d,i){ return color(i); })
    .attr("d", arc);

  arcs.append("text")
    .style("cursor", cursorf)
    .on("click", function(d,i){ goto_page(legend[i]); })
    .attr("transform", function(d) { return "translate(" + arc.centroid(d) + ")"; })
    .attr("dy", ".35em")
    .attr("text-anchor", "middle")
    .attr("display", function(d) { return d.value/s > .05 ? null : "none"; })
  //    .attr("title", function(d,i){ return legend[i];})
    .text(function(d,i){ return (100*d.value/s).toFixed()+"%"; });

  /* Legend. */
  vis.selectAll(".legend")
    .data(legend)
    .enter().append("svg:text")
    .on("click", function(d,i){ goto_page(legend[i]); })
    .attr("display", function(d,i) { return data[i]/s > .05 ? null : "none"; })
    .attr("class", "legend")
    .attr("x", w+40)
    .attr("y", function(d,i){ return 20+16*i; })
    .style("cursor", cursorf)
    .style("font", "12px sans-serif")
    .text(String);

  vis.selectAll(".legendmark")
    .data(legend)
    .enter().append("svg:path")
    .style("cursor", cursorf)
    .on("click", function(d,i){ goto_page(legend[i]); })
    .attr("class", "legendmark")
    .attr("display", function(d,i) { return data[i]/s > .05 ? null : "none"; })
    .attr("transform", function(d,i){ return "translate(" + (w+30) + "," + (17+16*i) + ")"; })
    .attr("d", function(d,i){ return d3.svg.symbol().type("circle").size(48).call(); })
    .style("stroke", function(d,i){ return color(i); })
    .style("fill", function(d,i){ return color(i); });
}
