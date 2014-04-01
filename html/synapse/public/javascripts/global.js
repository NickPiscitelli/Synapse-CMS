var redir;
function sendAJAX(url,data){
	$.ajax({
		type: 'POST',
		url: url,
		dataType: 'JSON',
		data: data,
		success: function(d){
			console.log(d);
			growler(d);
			redir = d.url;
			if(redir){
				setTimeout("window.location.href = redir;",1000);
			}
		},
		error: function(d){
			console.log(d);
			growler(d);
		}
	});
}

function growler(d){
	$.bootstrapGrowl(d.message, {
	  ele: 'body',
	  type: d.success ? 'success' : 'error',
	  offset: {from: 'top', amount: 35},
	  align: 'right',
	  width: 'auto',
	  delay: 4000,
	  allow_dismiss: true,
	  stackup_spacing: 15
	});
}

$(function(){
	// The system uses AJAX for all submissions. This
	// is to help prevent accidental triggering of
	// default form subs and receiving 404s.
	$('form').submit(function(e){
		if(!$(this).hasClass('allowSubmission')){
			e.preventDefault();
			return !1;
		}
	});
	if ($('div.editLink').length){
		$('#content div.page').hover(function(){
			$(this).find('div.editLink').first().show()
		},function(){
			$(this).find('div.editLink').first().hide()
		});
	}
});