
var appService = (function() {
    var serviceUrls = {
        test: function() { return "api/Data/Test"; },
        getSiteName: function() { return "api/Data/SiteName"; }
    };
    function ajaxRequest(type, url, data) {
        var options = {
            success: function() {},
            error: function(jqHXR, status, message) {
                alert(message);
            },
            url: url,
            headers: { Accept: "application/json" },
            contentType: "application/json",
            cache: false,
            type: type,
            timeout: 300000,
            data: data ? ko.toJSON(data) : null
        };
        return $.ajax(options);
    }
    return {
        test: function(data) {
            return ajaxRequest("get", serviceUrls.test(), data);
        },
        getSiteName: function(data) {
            return ajaxRequest("get", serviceUrls.getSiteName(), data);
        }
    };
})();

var ViewModel = function() {
    var self = this;
    self.label = ko.observable("Welcome");
    self.siteName = ko.observable("click to retrieve");
    self.testButtonClick = function() {
        return function() {
            appService.test().done(function(data) {
                self.label(data);
                appService.getSiteName().done(function(data) {
                    self.siteName(data);
                });
            });
        };
    };
};

$(document).ready(function() {
    // Get the parameters from the query string.
    var spHostUrl = decodeURIComponent(getQueryStringParameter("SPHostUrl"));
    var scriptBase = spHostUrl + "/_layouts/15/";
    // Load SP scripts on demand.
    $.getScript(scriptBase + "MicrosoftAjax.js").then(function() {
        return $.getScript(scriptBase + "SP.UI.Controls.js", renderChrome);
    }).then(function() {
        // Other custom startup.
        var model = new ViewModel();
        var mainElement = $("mainForm")[0];
        ko.applyBindings(model, mainElement);
    });
});

function getQueryStringParameter(paramToRetrieve) {
    var params = document.URL.split("?")[1].split("&");
    for (let i = 0; i < params.length; i++) {
        var singleParam = params[i].split("=");
        if (singleParam[0].toLowerCase() === paramToRetrieve.toLowerCase()) {
            return singleParam[1];
        }
    }
    return "";
}

function renderChrome() {
    var options = {
        "onCssLoaded": "chromeLoaded()"
    };
    var nav = new window.SP.UI.Controls.Navigation("chrome_ctrl_placeholder", options);
    nav.setVisible(true);
}

function chromeLoaded() {
    $("body").show();
}

