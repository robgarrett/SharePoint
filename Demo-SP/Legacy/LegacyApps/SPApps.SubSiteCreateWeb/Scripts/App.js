
$(document).ready(function() {
    $.getScript("../scripts/sp.ui.controls.js", renderChrome);
});

function renderChrome() {
    var options = {
        "appIconUrl": "../Images/AppIcon.png",
        "appTitle": "SP Sub Site Provisioner",
        "appHelpPageUrl": "help.html?" + document.URL.split("?")[1]
    }
    var nav = new SP.UI.Controls.Navigation("chrome_control_container", options);
    nav.setVisible(true);
}

