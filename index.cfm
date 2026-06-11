<cfset outputDir = expandPath("./output") />
<cfif NOT directoryExists(outputDir)>
    <cfdirectory action="create" directory="#outputDir#" />
</cfif>

<cfset pdfUtil = new PDFUtility() />

<html>
<head>
    <title>PDF Signature Utility</title>
</head>
<body>

<h2>PDF Signature Utility</h2>

<form method="post">

    <label>Signer Name:</label><br>
    <input
        type="text"
        name="signatureText"
        value="<cfoutput>#encodeForHTML(form.signatureText ?: '')#</cfoutput>"
        required
        style="width:300px;"
    >
    <br><br>

    <input type="submit" name="generatePDF" value="Generate PDF">

</form>

<hr>

<cfif structKeyExists(form, "generatePDF")>

    <cftry>

        <!--- Step 1: Append signature line --->
        <cfset mergedPDF = pdfUtil.addSignatureLine(
            PDFPath          = "D:\PDF-Utility\sample-local-pdf.pdf",
            SignaturePDFPath = "D:\PDF-Utility\signature_line.pdf",
            SaveToFolder     = outputDir
        ) />

        <!--- Step 2: Add signer name --->
        <cfset signedPDF = pdfUtil.addSignatureText(
            PDFPath       = mergedPDF,
            SignatureText = trim(form.signatureText),
            SaveToFolder  = outputDir
        ) />

        <cfoutput>
            <h3>PDF Generated Successfully</h3>

            Generated File:<br>
            #signedPDF#
        </cfoutput>

        <cfcatch type="any">
            <cfoutput>
                <div style="color:red;">
                    Error: #cfcatch.message#<br>
                    #cfcatch.detail#
                </div>
            </cfoutput>
        </cfcatch>

    </cftry>

</cfif>

</body>
</html>