<cfcomponent>

    <cfset this.name            = "PDFUtility" />
    <cfset this.sessionManagement = false />

    <!---
        Load standalone PDFBox JARs from the /jars folder.
        ColdFusion's built-in PDF libraries run in a separate OSGi
        classloader and are not reachable via createObject(); these
        JARs give user code its own isolated copy of PDFBox 3.x.

        Required JARs (download from Maven Central):
          pdfbox-3.0.x.jar      — https://search.maven.org/artifact/org.apache.pdfbox/pdfbox
          fontbox-3.0.x.jar     — https://search.maven.org/artifact/org.apache.pdfbox/fontbox
          commons-logging-1.3.x.jar — https://search.maven.org/artifact/commons-logging/commons-logging

        Place all three in D:\PDF-Utility\jars\ then restart the server.
    --->
    <cfset this.javaSettings = {
        loadPaths             = [ expandPath("./jars/") ],
        loadColdFusionClassPath = true,
        reloadOnChange        = false
    } />

</cfcomponent>
