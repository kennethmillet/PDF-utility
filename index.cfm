
<!--- Ensure the output folder exists before calling the utility --->
<cfset outputDir = expandPath("./output") />
<cfif NOT directoryExists(outputDir)>
    <cfdirectory action="create" directory="#outputDir#" />
</cfif>

<cfset pdfUtil = new PDFUtility() />


<!--- ============================================================
    Example 1 — addSignatureLine()
    Stamps the signature template onto the bottom-right of the last page.
============================================================ --->
<cftry>
    <cfset mergedPDF = pdfUtil.addSignatureLine(
        PDFPath          = "D:\PDF-Utility\sample.pdf",
        SignaturePDFPath = "D:\PDF-Utility\blank_signed.pdf",
        SaveToFolder     = outputDir
    ) />
    <cfoutput>Stamped PDF created: #mergedPDF#<br></cfoutput>

    <cfcatch type="PDFUtility.InvalidArgument">
        <cfoutput>Validation error: #cfcatch.message# — #cfcatch.detail#<br></cfoutput>
    </cfcatch>
    <cfcatch type="PDFUtility.ProcessingError">
        <cfoutput>Processing error: #cfcatch.message# — #cfcatch.detail#<br></cfoutput>
    </cfcatch>
    <cfcatch type="PDFUtility.WriteError">
        <cfoutput>Write error: #cfcatch.message# — #cfcatch.detail#<br></cfoutput>
    </cfcatch>
</cftry>


<!--- ============================================================
    Example 2 — addSignatureText()
    Overlays signer name and today's date just below the signature image.
    Pass the same SignaturePDFPath so the method can compute the placement.
============================================================ --->
<cftry>
    <cfset signedPDF = pdfUtil.addSignatureText(
        PDFPath          = "#mergedPDF#",
        SignaturePDFPath = "D:\PDF-Utility\blank_signed.pdf",
        SignatureText    = "K.M",
        SaveToFolder     = outputDir
    ) />
    <cfoutput>Signed PDF created: #signedPDF#<br></cfoutput>

    <cfcatch type="PDFUtility.InvalidArgument">
        <cfoutput>Validation error: #cfcatch.message# — #cfcatch.detail#<br></cfoutput>
    </cfcatch>
    <cfcatch type="PDFUtility.ProcessingError">
        <cfoutput>Processing error: #cfcatch.message# — #cfcatch.detail#<br></cfoutput>
    </cfcatch>
    <cfcatch type="PDFUtility.WriteError">
        <cfoutput>Write error: #cfcatch.message# — #cfcatch.detail#<br></cfoutput>
    </cfcatch>
</cftry>

