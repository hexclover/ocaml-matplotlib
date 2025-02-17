open Base
open Pyops

let pyplot_module = ref None

let maybe_py_init () =
  if not (Py.is_initialized ())
  then (
    Py.initialize ();
    (* Reinstall the default signal handler as it may have been
       overriden when launching python. *)
    Caml.Sys.(set_signal sigint Signal_default))

module Backend = struct
  type t =
    | Agg
    | Default
    | Other of string

  let to_string_option = function
    | Agg -> Some "Agg"
    | Default -> None
    | Other str -> Some str
end

let init_ backend =
  maybe_py_init ();
  let mpl = Py.import "matplotlib" in
  Option.iter (Backend.to_string_option backend) ~f:(fun backend_str ->
      ignore ((mpl.&("use")) [| Py.String.of_string backend_str |]));
  Py.import "matplotlib.pyplot"

let set_backend backend =
  let plt = init_ backend in
  pyplot_module := Some plt

let pyplot_module () =
  match !pyplot_module with
  | Some t -> t
  | None ->
    let t = init_ Default in
    pyplot_module := Some t;
    t

module Color = struct
  type t =
    | Red
    | Green
    | Blue
    | White
    | Black
    | Yellow
    | Orange
    | Other of string

  let to_pyobject t =
    let str =
      match t with
      | Red -> "red"
      | Green -> "green"
      | Blue -> "blue"
      | White -> "white"
      | Black -> "black"
      | Yellow -> "yellow"
      | Orange -> "orange"
      | Other str -> str
    in
    Py.String.of_string str
end

module Linestyle = struct
  type t =
    | Solid
    | Dotted
    | Other of string

  let to_pyobject t =
    let str =
      match t with
      | Solid -> "-"
      | Dotted -> ":"
      | Other str -> str
    in
    Py.String.of_string str
end

module Loc = struct
  type t =
    | Best
    | UpperRight
    | UpperLeft
    | LowerLeft
    | LowerRight
    | Right
    | CenterLeft
    | CenterRight
    | LowerCenter
    | UpperCenter
    | Center

  let to_pyobject t =
    let str = match t with
      | Best -> "best"
      | UpperRight -> "upper right"
      | UpperLeft -> "upper left"
      | LowerLeft -> "lower left"
      | LowerRight -> "lower right"
      | Right -> "right"
      | CenterLeft -> "center left"
      | CenterRight -> "center right"
      | LowerCenter -> "lower center"
      | UpperCenter -> "upper center"
      | Center -> "center"
    in Py.String.of_string str
end

let savefig filename =
  let p = pyplot_module () in
  ignore ((p.&("savefig")) [| Py.String.of_string filename |])

let plot_data format =
  let p = pyplot_module () in
  let format =
    match format with
    | `png -> "png"
    | `jpg -> "jpg"
  in
  let io = Py.import "io" in
  let bytes_io = (io.&("BytesIO")) [||] in
  let _ =
    Py.Module.get_function_with_keywords
      p
      "savefig"
      [| bytes_io |]
      [ "format", Py.String.of_string format ]
  in
  (bytes_io.&("getvalue")) [||] |> Py.String.to_string

let show () =
  let p = pyplot_module () in
  ignore ((p.&("show")) [||])

let figure ?num ?figsize ?dpi ?facecolor ?edgecolor ?frameon ?clear () =
  let p = pyplot_module () in
  let keywords =
    List.filter_opt
      [ Option.map num ~f:(fun num -> "num", Py.Int.of_int num)
      ; Option.map figsize ~f:(fun (w, h) -> "figsize", Py.Tuple.of_pair (Py.Float.of_float w, Py.Float.of_float h))
      ; Option.map dpi ~f:(fun dpi -> "dpi", Py.Float.of_float dpi)
      ; Option.map facecolor ~f:(fun fc -> "facecolor", Color.to_pyobject fc)
      ; Option.map edgecolor ~f:(fun ec -> "edgecolor", Color.to_pyobject ec)
      ; Option.map frameon ~f:(fun frameon -> "frameon", Py.Bool.of_bool frameon)
      ; Option.map clear ~f:(fun clear -> "clear", Py.Bool.of_bool clear)
      ]
  in
  ignore (Py.Module.get_function_with_keywords p "figure" [||] keywords)

let style_available () =
  let p = pyplot_module () in
  (p.@$("style")).@$("available") |> Py.List.to_list_map Py.String.to_string

let style_use s =
  let p = pyplot_module () in
  ignore (((p.@$("style")).&("use")) [| Py.String.of_string s |])

module Public = struct
  module Backend = Backend
  module Color = Color
  module Linestyle = Linestyle
  module Loc = Loc

  let set_backend = set_backend
  let show = show
  let figure = figure
  let savefig = savefig
  let plot_data = plot_data
  let style_available = style_available
  let style_use = style_use
end

let float_array_to_python xs = Py.List.of_array_map Py.Float.of_float xs

let call_plot_func p func ?label ?color ?linewidth ?linestyle ?xs ys =
  let keywords =
    List.filter_opt
      [ Option.map color ~f:(fun color -> "color", Color.to_pyobject color)
      ; Option.map linewidth ~f:(fun lw -> "linewidth", Py.Float.of_float lw)
      ; Option.map linestyle ~f:(fun ls -> "linestyle", Linestyle.to_pyobject ls)
      ; Option.map label ~f:(fun l -> "label", Py.String.of_string l)
      ]
  in
  let args =
    match xs with
    | Some xs -> [| float_array_to_python xs; float_array_to_python ys |]
    | None -> [| float_array_to_python ys |]
  in
  let func_name = match func with
  | `plot -> "plot"
  | `semilogy -> "semilogy"
  | `semilogx -> "semilogx"
  | `loglog -> "loglog"
  in
  ignore (Py.Module.get_function_with_keywords p func_name args keywords)

let plot p ?label ?color ?linewidth ?linestyle ?xs ys =
  call_plot_func p `plot ?label ?color ?linewidth ?linestyle ?xs ys

let semilogy p ?label ?color ?linewidth ?linestyle ?xs ys =
  call_plot_func p `semilogy ?label ?color ?linewidth ?linestyle ?xs ys

let semilogx p ?label ?color ?linewidth ?linestyle ?xs ys =
  call_plot_func p `semilogx ?label ?color ?linewidth ?linestyle ?xs ys

let loglog p ?label ?color ?linewidth ?linestyle ?xs ys =
  call_plot_func p `loglog ?label ?color ?linewidth ?linestyle ?xs ys

let fill_between p ?color ?alpha xs ys1 ys2 =
  let keywords = List.filter_opt
    [ Option.map color ~f:(fun color -> "color", Color.to_pyobject color)
    ; Option.map alpha ~f:(fun alpha -> "alpha", Py.Float.of_float alpha)
    ]
  in
  let args = Array.map [|xs; ys1; ys2|] float_array_to_python in
  ignore (Py.Module.get_function_with_keywords p "fill_between" args keywords)

let hist p ?label ?color ?bins ?weights ?orientation ?histtype ?xs ys =
  let keywords =
    List.filter_opt
      [ Option.map color ~f:(fun color -> "color", Color.to_pyobject color)
      ; Option.map label ~f:(fun l -> "label", Py.String.of_string l)
      ; Option.map bins ~f:(fun b -> "bins", Py.Int.of_int b)
      ; Option.map weights ~f:(fun w -> "weights", float_array_to_python w)
      ; Option.map orientation ~f:(fun o ->
            let o =
              match o with
              | `horizontal -> "horizontal"
              | `vertical -> "vertical"
            in
            "orientation", Py.String.of_string o)
      ; Option.map histtype ~f:(fun h ->
            let h =
              match h with
              | `bar -> "bar"
              | `barstacked -> "barstacked"
              | `step -> "step"
              | `stepfilled -> "stepfilled"
            in
            "histtype", Py.String.of_string h)
      ]
  in
  let args =
    match xs with
    | Some xs -> [| List.map (ys :: xs) ~f:float_array_to_python |> Py.List.of_list |]
    | None -> [| float_array_to_python ys |]
  in
  ignore (Py.Module.get_function_with_keywords p "hist" args keywords)

let scatter p ?s ?c ?marker ?alpha ?linewidths xys =
  let keywords =
    List.filter_opt
      [ Option.map c ~f:(fun c -> "c", Color.to_pyobject c)
      ; Option.map s ~f:(fun s -> "s", Py.Float.of_float s)
      ; Option.map marker ~f:(fun m -> "marker", String.of_char m |> Py.String.of_string)
      ; Option.map alpha ~f:(fun a -> "alpha", Py.Float.of_float a)
      ; Option.map linewidths ~f:(fun l -> "linewidths", Py.Float.of_float l)
      ]
  in
  let xs = Py.List.of_array_map (fun (x, _) -> Py.Float.of_float x) xys in
  let ys = Py.List.of_array_map (fun (_, y) -> Py.Float.of_float y) xys in
  ignore (Py.Module.get_function_with_keywords p "scatter" [| xs; ys |] keywords)

let scatter_3d p ?s ?c ?marker ?alpha ?linewidths xyzs =
  let keywords =
    List.filter_opt
      [ Option.map c ~f:(fun c -> "c", Color.to_pyobject c)
      ; Option.map s ~f:(fun s -> "s", Py.Float.of_float s)
      ; Option.map marker ~f:(fun m -> "marker", String.of_char m |> Py.String.of_string)
      ; Option.map alpha ~f:(fun a -> "alpha", Py.Float.of_float a)
      ; Option.map linewidths ~f:(fun l -> "linewidths", Py.Float.of_float l)
      ]
  in
  let xs = Py.List.of_array_map (fun (x, _, _) -> Py.Float.of_float x) xyzs in
  let ys = Py.List.of_array_map (fun (_, y, _) -> Py.Float.of_float y) xyzs in
  let zs = Py.List.of_array_map (fun (_, _, z) -> Py.Float.of_float z) xyzs in
  ignore (Py.Module.get_function_with_keywords p "scatter" [| xs; ys; zs |] keywords)

let bar p ?width ?bottom ?align xs heights =
  let keywords = List.filter_opt
      [ Option.map width ~f:(fun width -> "width", Py.Float.of_float width)
      ; Option.map bottom ~f:(fun bottom -> "bottom", Py.Float.of_float bottom)
      ; Option.map align ~f:(fun align ->
            let align =
              match align with
              | `center -> "center"
              | `edge -> "edge"
            in
            "align", Py.String.of_string align)
      ]
  in
  let xs = Py.List.of_array_map Py.Float.of_float xs in
  let heights = Py.List.of_array_map Py.Float.of_float heights in
  ignore (Py.Module.get_function_with_keywords p "bar" [| xs; heights |] keywords)

let stairs p ?edges ?orientation ?baseline ?fill values =
  let keywords = List.filter_opt
      [ Option.map edges ~f:(fun edges -> "edges", Py.List.of_array_map Py.Float.of_float edges)
      ; Option.map orientation ~f:(fun o ->
            let o =
              match o with
              | `horizontal -> "horizontal"
              | `vertical -> "vertical"
            in
            "orientation", Py.String.of_string o)
      ; Option.map baseline ~f:(fun baseline -> "baseline", Py.Float.of_float baseline)
      ; Option.map fill ~f:(fun fill -> "fill", Py.Bool.of_bool fill)
      ]
  in
  let values = Py.List.of_array_map Py.Float.of_float values in
  ignore (Py.Module.get_function_with_keywords p "staris" [| values |] keywords)

module Imshow_data = struct
  type 'a data =
    | Scalar of 'a array array
    | Rgb of ('a * 'a * 'a) array array
    | Rgba of ('a * 'a * 'a * 'a) array array

  type 'a typ_ =
    | Int : int typ_
    | Float : float typ_

  let int = Int
  let float = Float

  type t = P : ('a data * 'a typ_) -> t

  let scalar typ_ data = P (Scalar data, typ_)
  let rgb typ_ data = P (Rgb data, typ_)
  let rgba typ_ data = P (Rgba data, typ_)

  let to_pyobject (P (data, typ_)) =
    let to_pyobject ~scalar_to_pyobject =
      match data with
      | Scalar data ->
        Py.List.of_array_map (Py.List.of_array_map scalar_to_pyobject) data
      | Rgb data ->
        let rgb_to_pyobject (r, g, b) =
          (scalar_to_pyobject r, scalar_to_pyobject g, scalar_to_pyobject b)
          |> Py.Tuple.of_tuple3
        in
        Py.List.of_array_map (Py.List.of_array_map rgb_to_pyobject) data
      | Rgba data ->
        let rgba_to_pyobject (r, g, b, a) =
          ( scalar_to_pyobject r
          , scalar_to_pyobject g
          , scalar_to_pyobject b
          , scalar_to_pyobject a )
          |> Py.Tuple.of_tuple4
        in
        Py.List.of_array_map (Py.List.of_array_map rgba_to_pyobject) data
    in
    match typ_ with
    | Int -> to_pyobject ~scalar_to_pyobject:Py.Int.of_int
    | Float -> to_pyobject ~scalar_to_pyobject:Py.Float.of_float
end

let imshow p ?cmap data =
  let keywords =
    List.filter_opt [ Option.map cmap ~f:(fun c -> "cmap", Py.String.of_string c) ]
  in
  let data = Imshow_data.to_pyobject data in
  ignore (Py.Module.get_function_with_keywords p "imshow" [| data |] keywords)

let legend p ?labels ?loc () =
  let keywords = List.filter_opt
    [ Option.map labels ~f:(fun labels -> "labels",
       Py.List.of_array_map Py.String.of_string labels)
    ; Option.map loc ~f:(fun loc -> "loc", Loc.to_pyobject loc)
    ] in
  ignore (Py.Module.get_function_with_keywords p "legend" [||] keywords)
