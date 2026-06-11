<!--- Ensure the output folder exists before calling the utility --->
<cfset outputDir = expandPath("./output") />
<cfif NOT directoryExists(outputDir)>
    <cfdirectory action="create" directory="#outputDir#" />
</cfif>
<!--- Ensure the upload folder exists --->
<cfset uploadDir = expandPath("./uploads") />
<cfif NOT directoryExists(uploadDir)>
    <cfdirectory action="create" directory="#uploadDir#" />
</cfif>

<cfset pdfUtil = new PDFUtility() />

<html>
<head>
    <title>PDF Signature Utility</title>
</head>
<body>

<h2>PDF Signature Utility</h2>

<form method="post" enctype="multipart/form-data">

    <p>
        <label>Select PDF:</label>  <br>
        <input type="file" name="pdfFile" accept=".pdf" required>
    </p>

    <p>
        <label>Signer Name:</label> <br>
        <input type="text" name="signatureText" required style="width:300px;">
    </p>

    <p>
        <input type="submit" name="generatePDF" value="Generate Signed PDF">
    </p>

</form>

<hr>

<cfif structKeyExists(form, "generatePDF")>

    <cftry>

        <!--- Upload PDF --->
        <cffile
            action="upload"
            fileField="pdfFile"
            destination="#uploadDir#"
            nameConflict="makeunique"
            accept="application/pdf">

        <cfset uploadedPDF = cffile.serverDirectory & "\" & cffile.serverFile />

        <!--- Append signature block --->
        <cfset mergedPDF = pdfUtil.addSignatureLine(
            PDFPath          = uploadedPDF,
            SignaturePDFPath = "D:\PDF-Utility\signature_line.pdf",
            SaveToFolder     = outputDir
        ) />

        <!--- Add signature text --->
        <cfset signedPDF = pdfUtil.addSignatureText(
            PDFPath       = mergedPDF,
            SignatureText = trim(form.signatureText),
            SaveToFolder  = outputDir
        ) />

        <cfoutput>
            <h3>PDF Generated Successfully</h3>

            Original File:<br>
            #uploadedPDF#<br><br>

            Signed File:<br>
            #signedPDF#
        </cfoutput>

        <cfcatch type="any">
            <cfoutput>
                <div style="color:red;">
                    <strong>Error:</strong><br>
                    #cfcatch.message#<br>
                    #cfcatch.detail#
                </div>
            </cfoutput>
        </cfcatch>

    </cftry>

</cfif>

</body>
</html>