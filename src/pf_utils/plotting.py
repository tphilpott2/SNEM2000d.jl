import powerfactory


# gets or creates a page in the graphics window
def get_page(app, page_name, clear=True, page_frame=None, page_attributes={}):
    grb = app.GetFromStudyCase("SetDesktop")
    grb.Show()
    if clear == True:
        try:
            page = grb.GetPage(page_name)
            page.RemovePage()
        except:
            None
    page = grb.GetPage(page_name, 1)
    if page_frame is not None:
        try:
            page.GetContents("*.SetGrfpage")[0].aDrwFrm = page_frame
        except:
            app.PrintInfo(f"{page_frame} not defined")
    for attr, value in page_attributes.items():
        page.SetAttribute(attr, value)
    return page


# makes or gets a plot in the page
def make_plot(app, plot_name, page, reset=True, dev=False):
    plot = page.GetOrInsertCurvePlot(plot_name, 1)
    leg = plot.GetLegend()
    leg.showLegend = 0
    # add curves to plot
    ds = plot.GetDataSeries()
    if reset == True:
        ds.ClearCurves()
    if dev == True:
        try:
            filt = ds.GetContents("SetCrvfilt")[0]
        except:
            filt = ds.CreateObject("SetCrvfilt")
        filt.SetAttribute("iopt_use", "dev")
    return plot
