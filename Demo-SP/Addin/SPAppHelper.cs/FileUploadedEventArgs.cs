using System;

namespace SPAppHelper
{
    public class FileUploadedEventArgs : EventArgs
    {
        public string Filename { get; set;  }

        public FileUploadedEventArgs(string filename)
        {
            Filename = filename;
        }
    }
}
