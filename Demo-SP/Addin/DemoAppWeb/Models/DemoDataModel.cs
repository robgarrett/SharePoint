using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Web;

namespace DemoAppWeb.Models
{
    public class DemoDataModel
    {
        public enum EventType {  INFO, WARN, ERROR};

        [Required(ErrorMessage = "The Document Library Name is required.")]
        public string DocumentLibraryName { get; set; }
        [Required(ErrorMessage = "The View Name is required.")]
        public string ViewName { get; set; }
        [Required(ErrorMessage = "The Page Name is required.")]
        public string PageName { get; set; }
        public HttpPostedFileBase file1 { get; set;  }
        public HttpPostedFileBase file2 { get; set; }
        public HttpPostedFileBase file3 { get; set; }
        public string SPHostUrl { get; set; }
        public string SPLanguage { get; set; }
        public string SPClientTag { get; set; }
        public string SPProductNumber { get; set; }

        public ICollection<KeyValuePair<string, EventType>> Messages { get; private set; }

        public DemoDataModel()
        {
            Messages = new List<KeyValuePair<string, EventType>>();
        }
    }
}